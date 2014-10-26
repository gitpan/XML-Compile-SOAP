# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP11::Operation;
use vars '$VERSION';
$VERSION = '2.11';

use base 'XML::Compile::Operation';

use Log::Report 'xml-report-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:soap11/;
use XML::Compile::SOAP11::Client;
use XML::Compile::SOAP11::Server;

XML::Compile->knownNamespace(&WSDL11SOAP => 'wsdl-soap.xsd');
__PACKAGE__->register(WSDL11SOAP, SOAP11ENV);

# client/server object per schema class, because initiation options
# can be different.  Class reference is key.
my (%soap11_client, %soap11_server);


sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{$_}    = $args->{$_} || {}
        for qw/input_def output_def fault_def/;

    $self->{style} = $args->{style} || 'document';
    $self;
}

sub _initWSDL11($)
{   my ($class, $wsdl) = @_;

    trace "initialize SOAP11 operations for WSDL11";

    $wsdl->importDefinitions(WSDL11SOAP, element_form_default => 'qualified');
    $wsdl->prefixes
      ( soap => WSDL11SOAP
      );

    $wsdl->declare(READER =>
      [ "soap:address", "soap:operation", "soap:binding"
      , "soap:body",    "soap:header",    "soap:fault" ]);
}

sub _fromWSDL11(@)
{   my ($class, %args) = @_;

    # Extract the SOAP11 specific information from a WSDL11 file.  There are
    # half a zillion parameters.
    my ($p_op, $b_op, $wsdl)
      = @args{ qw/port_op bind_op wsdl/ };

    $args{schemas}   = $wsdl;
    $args{endpoints} = $args{serv_port}{soap_address}{location};

    my $sop = $b_op->{soap_operation}     || {};
    $args{action}  ||= $sop->{soapAction} || '';

    my $sb = $args{binding}{soap_binding} || {};
    $args{transport} = $sb->{transport}   || 'HTTP';
    $args{style}     = $sb->{style}       || 'document';

    $args{input_def} = $class->_msg_parts($wsdl, $args{name}, $args{style}
       , $p_op->{wsdl_input}, $b_op->{wsdl_input});

    $args{output_def} = $class->_msg_parts($wsdl, $args{name}, $args{style}
      , $p_op->{wsdl_output}, $b_op->{wsdl_output});

    $args{fault_def}
      = $class->_fault_parts($wsdl, $p_op->{wsdl_fault}, $b_op->{wsdl_fault});

    $class->SUPER::new(%args);
}

sub _msg_parts($$$$$)
{   my ($class, $wsdl, $opname, $style, $port_op, $bind_op) = @_;
    my %parts;

    defined $port_op          # communication not in two directions
        or return ({}, {});

    if(my $body = $bind_op->{soap_body})
    {   my $msgname   = $port_op->{message};
        my @parts     = $class->_select_parts($wsdl, $msgname, $body->{parts});

        my ($ns, $local) = unpack_type $msgname;
        my $procedure;
        if($style eq 'rpc')
        {   exists $body->{namespace}
                or error __x"rpc operation {name} requires namespace attribute"
                     , name => $msgname;
            my $ns = $body->{namespace};
            $procedure = pack_type $ns, $opname;
        }
        else
        {   $procedure = @parts==1 && $parts[0]{type} ? $msgname : $local; 
        }

        $parts{body}  = {procedure => $procedure, %$port_op, use => 'literal',
           %$body, parts => \@parts};
    }

    my $bsh = $bind_op->{soap_header} || [];
    foreach my $header (ref $bsh eq 'ARRAY' ? @$bsh : $bsh)
    {   my $msgname  = $header->{message};
        my @parts    = $class->_select_parts($wsdl, $msgname, $header->{part});
         push @{$parts{header}}, { %$header, parts => \@parts };

        foreach my $fault ( @{$header->{headerfault} || []} )
        {   $msgname = $fault->{message};
            my @hf   = $class->_select_parts($wsdl, $msgname, $fault->{part});
            push @{$parts{headerfault}}, { %$fault,  parts => \@hf };
        }
    }
    \%parts;
}

sub _select_parts($$$)
{   my ($class, $wsdl, $msgname, $need_parts) = @_;
    my $msg = $wsdl->findDef(message => $msgname)
        or error __x"cannot find message {name}", name => $msgname;

    my @need
      = ref $need_parts     ? @$need_parts
      : defined $need_parts ? $need_parts
      : ();

    my $parts = $msg->{wsdl_part} || [];
    @need or return @$parts;

    my @sel;
    my %parts = map { ($_->{name} => $_) } @$parts;
    foreach my $name (@need)
    {   my $part = $parts{$name}
            or error __x"message {msg} does not have a part named {part}"
                  , msg => $msg->{name}, part => $name;

        push @sel, $part;
    }

    @sel;
}

sub _fault_parts($$$)
{   my ($class, $wsdl, $portop, $bind) = @_;

    my $port_faults  = $portop || [];
    my %faults;

    my @sel;
    foreach my $fault (map {$_->{soap_fault}} @$bind)
    {   my $name  = $fault->{name};

        my $port  = first {$_->{name} eq $name} @$port_faults;
        defined $port
            or error __x"cannot find port for fault {name}", name => $name;

        my $msgname = $port->{message}
            or error __x"no fault message name in portOperation";

        my $message = $wsdl->findDef(message => $msgname)
            or error __x"cannot find fault message {name}", name => $msgname;

        @{$message->{wsdl_part} || []}==1
            or error __x"fault message {name} must have one part exactly"
                  , name => $msgname;

        $faults{$name} =
          { part => $message->{wsdl_part}[0]
          , use  => ($fault->{use} || 'literal')
          };
    }

    {faults => \%faults };
}

#-------------------------------------------


sub style()     {shift->{style}}
sub version()   { 'SOAP11' }
sub serverClass { 'XML::Compile::SOAP11::Server' }
sub clientClass { 'XML::Compile::SOAP11::Client' }

#-------------------------------------------


sub compileHandler(@)
{   my ($self, %args) = @_;

    my $soap = $soap11_server{$self->{schemas}}
      ||= XML::Compile::SOAP11::Server->new(schemas => $self->{schemas});
    my $style = $args{style} ||= $self->style;
    my $kind  = $args{kind} ||= $self->kind;

    my @ro    = (%{$self->{input_def}},  %{$self->{fault_def}});
    my @so    = (%{$self->{output_def}}, %{$self->{fault_def}});
    my $fo    = $self->{input_def};

    $soap->compileHandler
      ( name      => $self->name
      , kind      => $kind
      , selector  => $soap->compileFilter(%$fo)
      , encode    => $soap->_sender(@so, %args)
      , decode    => $soap->_receiver(@ro, %args)
      , callback  => $args{callback}
      );
}


sub compileClient(@)
{   my ($self, %args) = @_;

    my $soap = $soap11_client{$self->{schemas}}
      ||= XML::Compile::SOAP11::Client->new(schemas => $self->{schemas});
    my $style = $args{style} ||= $self->style;
    my $kind  = $args{kind}  ||= $self->kind;

    my @so   = (%{$self->{input_def}},  %{$self->{fault_def}});
    my @ro   = (%{$self->{output_def}}, %{$self->{fault_def}});

    $soap->compileClient
      ( name         => $self->name
      , kind         => $kind
      , encode       => $soap->_sender(@so, %args)
      , decode       => $soap->_receiver(@ro, %args)
      , transport    => $self->compileTransporter(%args)
      );
}

1;
