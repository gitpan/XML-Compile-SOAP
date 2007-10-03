# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP12;
use vars '$VERSION';
$VERSION = '0.55';
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

my $base  = 'http://www.w3.org/2003/05';

my $role  = "$base/soap-envelope/role";
my %roles =
 ( NEXT     => "$role/next"
 , NONE     => "$role/none"
 , ULTIMATE => "$role/ultimateReceiver"
 );

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( "$base/soap-encoding" => '2003-soap-encoding.xsd'
 , "$base/soap-envelope" => '2003-soap-envelope.xsd'
 , "$base/soap-rpc"      => '2003-soap-rpc.xsd'
 );


sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    my $env = $args->{envelope_ns} ||= "$base/soap-envelope";
    my $enc = $args->{encoding_ns} ||= "$base/soap-encoding";
    $self->SUPER::init($args);

    my $rpc = $self->{rpc} = $args->{rpc} || "$base/soap-rpc";

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $schemas->importDefinitions($rpc);
    $self;
}


sub rpcNS() {shift->{rpc}}

sub writer($)
{   my ($self, $args) = @_;

    error __x"headerfault does only exist in SOAP1.1"
        if $args->{header_fault};

}


sub roleAbbreviation($) { $roles{$_[1]} || $_[1] }


sub prepareServer($)
{   my ($self, $server) = @_;
}

1;
