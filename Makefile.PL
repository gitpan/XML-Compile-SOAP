use ExtUtils::MakeMaker;

use 5.008;

my $version = '3.06';

my $prereq =
   { XML::Compile         => '1.48'
   , XML::Compile::Tester => '0.90'
   , XML::Compile::Cache  => '1.03'
   , Log::Report          => '1.05'

   , LWP               => 5.816
   , Time::HiRes       => 0
   , File::Slurp::Tiny => 0

   , Test::More        => 0.54
   };

eval "require XML::Compile::WSDL11";
if($@ !~ /can\'t locate/i)
{   my $v = $XML::Compile::WSDL11::VERSION || '3.00';

    # results in dependency loop, which CPAN.pm cannot handle
    #$prereq->{'XML::Compile::WSDL11'} = '3.00';

    if($v < 3.00) { warn <<'__CHANGES_300'; sleep 10 }
******************************************************************
WARNING: with XML::Compile::SOAP11 v3.00, the WSDL11 code got
   moved into a separate module.  You may need to add dependencies
   to that module as well.
******************************************************************
__CHANGES_300
}

eval "require XML::Compile::SOAP::Daemon";
$prereq->{'XML::Compile::SOAP::Daemon'} = '3.00'
    unless $@ || $ENV{MARKOV_DEVEL};

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP'
 , VERSION	=> $version
 , PREREQ_PM    => $prereq
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'SOAP version 1.1'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

EXTENDS		= ../XMLCompile:../XMLDaemon:../XMLTester:../XMLCache:../XMLWSDL:../XMLSOAP12:../XMLSOAPEv:../XMLWSA

# for DIST
RAWDIR          = ../public_html/xml-compile-soap/raw
DISTDIR         = ../public_html/xml-compile-soap/source
LICENSE         = artistic
SKIP_LINKS	= XML::LibXML

# for POD
FIRST_YEAR      = 2007
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/
PODTAIL		= ../XML-shared-podtail
__POSTAMBLE
