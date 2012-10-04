package DBI::SpeedySimple;

use 5.010001;
use strict;
use warnings;

require DBI;
use Encode;

our $VERSION = '0.03';

sub new {
	my $self = bless {}, shift;
	$self->{dbh} = DBI->connect(shift) or die "Cannot connect: $DBI::errstr";
	return $self;
}

sub cache {
	my($self, $to_cache) = @_;
	$self->{cache} = bless {};
	for(@{$to_cache}) {
		my $ckey = join '-', ($_->{table}, @{$_->{indices}});
		$self->{cache}->{$ckey} = $self->{dbh}->selectall_hashref('SELECT * FROM ' . $_->{table}, $_->{indices});
		if(defined $self->{cache}->{$ckey}) {
			_cache_mark_utf8($self->{cache}->{$ckey}, scalar(@{$_->{indices}}));
		}
	}
	return;
}

sub _cache_mark_utf8 {
	my($cache, $index_depth) = @_;
	if($index_depth == 0) {
		for(keys %$cache) {
			Encode::_utf8_on($cache->{$_});
		}
	}
	elsif($index_depth > 0) {
		my $new_depth = $index_depth - 1;
		for(keys %$cache) {
			_cache_mark_utf8($cache->{$_}, $new_depth);
		}
	}
	else {
		die 'bad index depth in cache';
	}
	return;
}

sub fetch {
	my($self, $table, $what, $whereinfo, $limit) = @_;
	my $ckey = join('-', ($table, keys %{$whereinfo}));
	if(defined $self->{cache}->{$ckey}) {
		my $ptr = $self->{cache}->{$ckey};
		for(values %{$whereinfo}) {
			$ptr = $ptr->{$_};
		}
		return $ptr if defined $ptr;
	}
	
	my $sth = $self->{dbh}->prepare_cached("SELECT " . join(",", @$what) . " FROM `$table`" . $self->_whereinfo($whereinfo) . ($limit ? "LIMIT $limit" : "")) or die $DBI::errstr;
	my @vals = values(%{$whereinfo});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	my $r = int($limit) == 1 ? $sth->fetchrow_hashref() : $sth->fetchall_hashref();
	$sth->finish();
	if(defined $r) {
		Encode::_utf8_on($r->{$_}) for keys %$r;
	}
	return $r;
}

sub exists {
	my($self, $table, $whereinfo) = @_;
	my $sth = $self->{dbh}->prepare_cached("SELECT count(*) FROM $table" . $self->_whereinfo($whereinfo)) or die $DBI::errstr;
	my @vals = values(%{$whereinfo});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	my($count) = $sth->fetchrow_array();
	$sth->finish();
	return $count;
}

sub insert {
	my($self, $table, $info) = @_;
	my $sth = $self->{dbh}->prepare_cached("INSERT INTO $table (" . join(",", map { "`$_`" } keys(%{$info})) . ") VALUES(" . join(",", map {"?"} keys(%{$info})) . ")");
	my @vals = values(%{$info});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	$sth->finish();
}

sub update {
	my($self, $table, $info, $whereinfo) = @_;
	my $sth = $self->{dbh}->prepare_cached("UPDATE $table SET `" . join("`=?,`", keys(%{$info})) . "`=?" . $self->_whereinfo($whereinfo));
	my @vals = (values(%$info), values(%$whereinfo));
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	$sth->finish();
}

sub set {
	my($self, $table, $info, $whereinfo) = @_;
	return $self->update($table, $info, $whereinfo) if $self->exists($table, $whereinfo);
	return $self->insert($table, $info);
}

sub remove {
	my($self, $table, $whereinfo) = @_;
	if($self->{caching} and defined $self->{cache}->{join('-', ($table, keys %{$whereinfo}))}) {
		my $ptr = $self->{cache}->{join('-', ($table, keys %{$whereinfo}))};
		my @keys = keys %{$whereinfo};
		while(my $index = shift @keys) {
			if(!scalar(@keys)) {
				delete $ptr->{$whereinfo->{$index}};
			}
			else {
				$ptr = $ptr->{$whereinfo->{$index}};
			}
		}
	}
	
	my $sth = $self->{dbh}->prepare_cached("DELETE FROM $table" . $self->_whereinfo($whereinfo));
	my @vals = values(%{$whereinfo});
	for(@vals) {
		utf8::upgrade($_)
	}
	$sth->execute(@vals);
	$sth->finish();
}

sub _whereinfo {
	my($self, $whereinfo) = @_;
	return scalar(keys %{$whereinfo}) ? " WHERE " . join(" and ",  map { "$_=?" } keys(%{$whereinfo})) : "";
}

1;
__END__
=head1 NAME

DBI::SpeedySimple - provide a simple interface to DBI for basic queries
along with basic memory caching and automatic utf8 conversion.

=head1 SYNOPSIS

  use DBI::SpeedySimple;
  
  my $db = DBI::SpeedySimple->new("dbi:SQLite:example.db");
  
  # Cache the contents of the files table in memory for quick access
  # when fetching with filename and size as the where clause.
  $db->cache([{table => "files", indices => ["filename", "size"]}]);
  
  # This probably doesn't even work...
  $result = $db->fetch("files", ['filename', 'size'], {filename => "foo"});
  $result->{foo}->{size};
  
  # This does, though.
  $result = $db->fetch("files", ['filename', 'size'], {filename => "foo"}, 1);
  $result->{size};
  
  # Will return true if a row in files with filename="foo" exists.
  $result = $db->exists("files", {filename => "foo"});
  
  $db->insert("files", {filename => "foo", size => 3});
  
  # Update files size=6 where filename="foo";
  $db->update("files", {size => 6}, {filename => "foo"});
  
  # Decides whether to insert a new row or update an existing one based on the where clause.
  $db->set("files", {filename => "foo", size => 6}, {filename => "foo"});
  
  # WARNING: This function currently does not remove the row from the memory cache as it should.
  $db->remove("files", {filename => "foo"});
  
  # DBI can still be accessed for more complex queries.
  $result = $db->{dbh}->selectone_arrayref("SELECT size, filename FROM files");

=head1 DESCRIPTION

DBI::SpeedySimple is a very simplistic interface for L<DBI> that aims to simplfy
and speed up writing common database calls.

The main differences from the helper functions found within L<DBI> itself are: 
 - usage of prepare_cached rather than prepare
 - the ability to load a table into a transparent cache in RAM to speed access
 - functions are not called with SQL queries but the table name and a somewhat
   more perlish representation of data. Substitutions are handled for you.
 - it assumes the database uses utf8, encoding everything it sends and decoding
   everything it receives as utf8.

=head1 SEE ALSO

L<DBI>

=head1 BUGS

DBI::SpeedySimple->remove doesn't remove rows from the memory cache at this
time, only from the actual database.

=head1 AUTHOR, COPYRIGHT, AND LICENSE

Copyright (c) 2010, Kulag <g.kulag@gmail.com>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

=head1 REPOSITORY

http://github.com/Kulag/DBI-SpeedySimple

=cut
