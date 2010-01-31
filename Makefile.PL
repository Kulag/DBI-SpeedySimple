use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'DBI::SpeedySimple',
    VERSION_FROM      => 'lib/DBI/SpeedySimple.pm', # finds $VERSION
    PREREQ_PM         => {DBI => 1.21, Encode => 2.0}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/DBI/SpeedySimple.pm', # retrieve abstract from module
       AUTHOR         => 'Kulag <g.kulag@gmail.com>') : ()),
);
