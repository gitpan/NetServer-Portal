use ExtUtils::MakeMaker;

WriteMakefile(
	      PREREQ_PM => { Event => '0.70', Storable => '0.6' },
	      VERSION_FROM => "./lib/NetServer/Portal.pm",
	      NAME => 'NetServer::Portal',
	     );
