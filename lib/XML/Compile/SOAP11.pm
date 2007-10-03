# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP11;
use vars '$VERSION';
$VERSION = '0.55';
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util  qw/pack_type unpack_type/;

my $base       = 'http://schemas.xmlsoap.org/soap';
my $actor_next = "$base/actor/next";
my $soap11_env = "$base/envelope/";
my $soap12_env = 'http://www.w3c.org/2003/05/soap-envelope';

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( "$base/encoding/" => 'soap-encoding.xsd'
 , $soap11_env       => 'soap-envelope.xsd'
 );


sub new($@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    my $env = $args->{envelope_ns} ||= "$base/envelope/";
    my $enc = $args->{encoding_ns} ||= "$base/encoding/";
    $self->SUPER::init($args);

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $self;
}


sub writerHeaderEnv($$$$)
{   my ($self, $code, $allns, $understand, $actors) = @_;
    $understand || $actors or return $code;

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

    # Cannot precompile everything, because $doc is unknown
    my $ucode;
    if($understand)
    {   my $u_w = $self->{soap11_u_w} ||=
          $schema->compile
            ( WRITER => pack_type($envns, 'mustUnderstand')
            , output_namespaces    => $allns
            , include_namespaces   => 0
            );

        $ucode =
        sub { my $el = $code->(@_) or return ();
              my $un = $u_w->($_[0], 1);
              $el->addChild($un) if $un;
              $el;
            };
    }
    else {$ucode = $code}

    if($actors)
    {   $actors =~ s/\b(\S+)\b/$self->roleAbbreviation($1)/ge;

        my $a_w = $self->{soap11_a_w} ||=
          $schema->compile
            ( WRITER => pack_type($envns, 'actor')
            , output_namespaces    => $allns
            , include_namespaces   => 0
            );

        return
        sub { my $el  = $ucode->(@_) or return ();
              my $act = $a_w->($_[0], $actors);
              $el->addChild($act) if $act;
              $el;
            };
    }

    $ucode;
}

sub writer($)
{   my ($self, $args) = @_;
    $args->{prefix_table}
     = [ ''         => 'do not use'
       , 'SOAP-ENV' => $self->envelopeNS
       , 'SOAP-ENC' => $self->encodingNS
       , xsd        => 'http://www.w3.org/2001/XMLSchema'
       , xsi        => 'http://www.w3.org/2001/XMLSchema-instance'
       ];

    $self->SUPER::writer($args);
}

sub writerConvertFault($$)
{   my ($self, $faultname, $data) = @_;
    my %copy = %$data;

    my $code = delete $copy{Code};
    $copy{faultcode} ||= $self->convertCodeToFaultcode($faultname, $code);

    my $reasons = delete $copy{Reason};
    $copy{faultstring} = $reasons->[0]
        if ! $copy{faultstring} && ref $reasons eq 'ARRAY';

    delete $copy{Node};
    my $role  = delete $copy{Role};
    my $actor = delete $copy{faultactor} || $role;
    $copy{faultactor} = $self->roleAbbreviation($actor) if $actor;
}

sub convertCodeToFaultcode($$)
{   my ($self, $faultname, $code) = @_;

    my $value = $code->{Value}
        or error __x"SOAP1.2 Fault {name} Code requires Value"
              , name => $faultname;

    my ($ns, $class) = unpack_type $value;
    $ns eq $soap12_env
        or error __x"SOAP1.2 Fault {name} Code Value {value} not in {ns}"
              , name => $faultname, value => $value, ns => $soap12_env;

    my $faultcode
      = $class eq 'Sender'   ? 'Client'
      : $class eq 'Receiver' ? 'Server'
      :                        $class;  # unchanged
      # DataEncodingUnknown MustUnderstand VersionMismatch

    for(my $sub = $code->{Subcode}; defined $sub; $sub = $sub->{Subcode})
    {   my $subval = $sub->{Value}
           or error __x"SOAP1.2 Fault {name} subcode requires Value"
              , name => $faultname;
        my ($subns, $sublocal) = unpack_type $subval;
        $faultcode .= '.' . $sublocal;
    }

    pack_type $soap11_env, $faultcode;
}



sub roleAbbreviation($) { $_[1] eq 'NEXT' ? $actor_next : $_[1] }


sub prepareServer($)
{   my ($self, $server) = @_;
}

1;
