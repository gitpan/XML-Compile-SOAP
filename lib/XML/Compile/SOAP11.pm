# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP11;
use vars '$VERSION';
$VERSION = '0.57';
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
    $class ne __PACKAGE__
        or error __x"only instantiate a SOAP11::Client or ::Server";
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;

    $args->{version}               ||= 'SOAP11';
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
    {   $actors =~ s/\b(\S+)\b/$self->roleURI($1)/ge;

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

sub sender($)
{   my ($self, $args) = @_;
    my $envns = $self->envelopeNS;
    $args->{prefix_table}
     = [ ''         => 'do not use'
       , 'SOAP-ENV' => $envns
       , 'SOAP-ENC' => $self->encodingNS
       , xsd        => 'http://www.w3.org/2001/XMLSchema'
       , xsi        => 'http://www.w3.org/2001/XMLSchema-instance'
       ];
    push @{$args->{body}}, Fault => pack_type($envns, 'Fault');

    $self->SUPER::sender($args);
}

sub receiver($)
{   my ($self, $args) = @_;
    my $envns = $self->envelopeNS;

    push @{$args->{body}}, Fault => pack_type($envns, 'Fault');

    $self->SUPER::receiver($args);
}


sub readerParseFaults($)
{   my ($self, $faults) = @_;
    my %rules;

    my $schema = $self->schemas;
    my @f      = @$faults;

    while(@f)
    {   my ($label, $element) = splice @f, 0, 2;
        $rules{$element} =  [$label, $schema->compile(READER => $element)];
    }

    sub
    {   my $data   = shift;
        my $faults = $data->{Fault} or return;

        my $reports = $faults->{detail} ||= {};
        my ($label, $details) = (header => undef);
        foreach my $type (sort keys %$reports)
        {   my $report  = $reports->{$type} || [];
            if($rules{$type})
            {   ($label, my $do) = @{$rules{$type}};
                $details = [ map { ($do->($_))[1] } @$report ];
            }
            else
            {   ($label, $details) = (unknown => $report);
            }
        }

        my ($code_ns, $code_err) = unpack_type $faults->{faultcode};
        my ($err, @sub_err) = split /\./, $code_err;
        $err = 'Receiver' if $err eq 'Server';
        $err = 'Sender'   if $err eq 'Client';

        my %nice =
          ( code   => $faults->{faultcode}
          , class  => [ $code_ns, $err, @sub_err ]
          , reason => $faults->{faultstring}
          );

        $nice{role}   = $self->roleAbbreviation($faults->{faultactor})
            if $faults->{faultactor};

        $nice{detail} = (@$details==1 ? $details->[0] : $details)
            if $details;

        $data->{$label}  = \%nice;
        $faults->{_NAME} = $label;
    };
}

sub replyMustUnderstandFault($)
{   my ($self, $type) = @_;

    { Fault =>
        { faultcode   => pack_type($self->envelopeNS, 'MustUnderstand')
        , faultstring => "SOAP mustUnderstand $type"
        }
    };
}

sub roleURI($) { $_[1] && $_[1] eq 'NEXT' ? $actor_next : $_[1] }

sub roleAbbreviation($) { $_[1] && $_[1] eq $actor_next ? 'NEXT' : $_[1] }



1;
