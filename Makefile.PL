use ExtUtils::MakeMaker;

WriteMakefile(
	      PREREQ_PM => { Event => '0.70', 'Event::Stats' => '0.53' },
	      VERSION_FROM => "./lib/NetServer/Portal.pm",
	      NAME => 'NetServer::Portal',
	     );
