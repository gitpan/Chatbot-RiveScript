use 5.008007;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Chatbot::RiveScript',
    VERSION_FROM      => 'lib/Chatbot/RiveScript.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Chatbot/RiveScript.pm', # retrieve abstract from module
       AUTHOR         => 'Cerone Kirsle <kirsle@cpan.org>') : ()),
);
