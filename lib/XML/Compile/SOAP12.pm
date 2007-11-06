# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP12;
use vars '$VERSION';
$VERSION = '0.6';
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::SOAP::Util qw/:soap12/;

my %roles =
 ( NEXT     => SOAP12NEXT
 , NONE     => SOAP12NONE
 , ULTIMATE => SOAP12ULTIMATE
 );
my %rroles = reverse %roles;

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( &SOAP12ENC => '2003-soap-encoding.xsd'
 , &SOAP12ENV => '2003-soap-envelope.xsd'
 , &SOAP12RPC => '2003-soap-rpc.xsd'
 );


sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $args->{version}               ||= 'SOAP12';
    my $env = $args->{envelope_ns} ||= SOAP12ENV;
    my $enc = $args->{encoding_ns} ||= SOAP12ENC;
    $self->SUPER::init($args);

    my $rpc = $self->{rpc} = $args->{rpc} || SOAP12RPC;

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $schemas->importDefinitions($rpc);
    $self;
}


sub rpcNS() {shift->{rpc}}

sub sender($)
{   my ($self, $args) = @_;

    error __x"headerfault does only exist in SOAP1.1"
        if $args->{header_fault};

    $self->SUPER::sender($args);
}

sub roleURI($) { $roles{$_[1]} || $_[1] }

sub roleAbbreviation($) { $rroles{$_[1]} || $_[1] }

1;
