# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.
use warnings;
use strict;

package XML::Compile::WSDL11::Operation;
use vars '$VERSION';
$VERSION = '0.73';


use Log::Report 'xml-report-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11 SOAP11HTTP/;


sub new(@)
{   my $class = shift;
    (bless {@_}, $class)->init;
}

sub init()
{   my $self = shift;
    my $name = $self->name;

    # autodetect namespaces used
    my $port = $self->port;
    my ($soapns, $version) = ($self->{soap_ns}, $self->{version})
      = exists $port->{pack_type WSDL11SOAP,  'address'}
      ? (WSDL11SOAP,   'SOAP11')
      : exists $port->{pack_type WSDL11SOAP12,'address'}
      ? (WSDL11SOAP12, 'SOAP12')
      : error __x"no supported namespace found for {operation}"
           , operation => $name;

    $self->schemas->importDefinitions($soapns);

    # This should be detected while parsing the WSDL because the order of
    # input and output is significant (and lost), but WSDL 1.1 simplifies
    # our life by saying that only 2 out-of 4 predefined types can actually
    # be used at present.
    my @order    = @{$self->portOperation->{_ELEMENT_ORDER}};
    my $wsdlns   = $self->wsdlNS;
    my $intype   = pack_type $wsdlns, 'input';
    my $outtype  = pack_type $wsdlns, 'output';
    my ($first_in, $first_out);
    for(my $i = 0; $i<@order; $i++)
    {   $first_in  = $i if !defined $first_in  && $order[$i] eq $intype;
        $first_out = $i if !defined $first_out && $order[$i] eq $outtype;
    }

    $self->{kind}
      = !defined $first_in     ? 'notification-operation'
      : !defined $first_out    ? 'one-way'
      : $first_in < $first_out ? 'request-response'
      :                          'solicit-response';

    $self->{protocol}  ||= 'HTTP';
    $self;
}


sub name()     {shift->{name}}
sub service()  {shift->{service}}
sub port()     {shift->{port}}
sub binding()  {shift->{binding}}
sub portType() {shift->{portType}}
sub wsdl()     {shift->{wsdl}}
sub wsdlNS()   {shift->{wsdl}->wsdlNamespace}
sub schemas()  {shift->{wsdl}->schemas}

sub portOperation() {shift->{port_op}}
sub bindOperation() {shift->{bind_op}}


sub soapNameSpace() {shift->{soap_ns}}
sub soapVersion()   {shift->{version}}


sub endPointAddresses()
{   my $self = shift;
    return @{$self->{addrs}} if $self->{addrs};

    my $soapns   = $self->soapNameSpace;
    my $addrtype = pack_type $soapns, 'address';

    my $addrxml  = $self->port->{$addrtype}
        or error __x"soap end-point address not found in service port";

    my $addr_r   = $self->schemas->compile(READER => $addrtype);

    my @addrs    = map {$addr_r->($_)->{location}} @$addrxml;
    $self->{addrs} = \@addrs;
    @addrs;
}


sub soapAction()
{   my $self = shift;
    return $self->{action}
        if exists $self->{action};

    my $optype = pack_type $self->soapNameSpace, 'operation';
    my $opdata = {};
    if(my $opxml = $self->bindOperation->{$optype})
    {   my $op_r = $self->schemas->compile(READER => $optype);
        my $binding
         = @$opxml > 1
         ? (first {$_->{style} eq $self->soapStyle} @$opxml)
         : $opxml->[0];

        $opdata = $op_r->($binding);
    }
    $self->{action} = $opdata->{soapAction};
}

sub soapStyle() { shift->{style} }

sub soapUse(;$)
{   my $self = shift;
    @_ ? ($self->{use} = shift) : $self->{use};
}


sub kind() {shift->{kind}}


sub compileClient(@)
{   my ($self, %args) = @_;

    #
    # which SOAP version to use
    #

    my $soapns = $self->soapNameSpace;
    my ($soap, $version);
    if($soapns eq WSDL11SOAP)
    {   require XML::Compile::SOAP11::Client;
        $soap    = $self->{soap11_client}
               ||= XML::Compile::SOAP11::Client->new(schemas => $self->schemas);
        $version = 'SOAP11';
    }
    elsif($soapns eq WSDL11SOAP12)
    {   require XML::Compile::SOAP12::Client;
        $soap    = $self->{soap12_client}
               ||= XML::Compile::SOAP12::Client->new(schemas => $self->schemas);
        $version = 'SOAP12';
    }
    else { panic "NameSpace $soapns not supported for WSDL11 operation" }

    #
    ### select the right binding
    #

    my $proto  = $args{protocol}  || $self->{protocol}
              || ($self->soapAction =~ m/^(\w+)\:/ ? uc($1) : 'HTTP');
    $proto     = SOAP11HTTP if $proto eq 'HTTP';

    my $style  = $args{style} || $self->soapStyle;
    if(defined $style)
    {   $self->canTransport($proto, $style)
            or error __x"transport {protocol} as {style} not defined in WSDL"
                  , protocol => $proto, style => $style;
    }
    elsif($self->canTransport($proto, 'document')) { $style = 'document' }
    elsif($self->canTransport($proto, 'rpc'))      { $style = 'rpc' }
    else
    {   error __x"transport {protocol} style not detected in WSDL"
          , protocol => $proto;
    }
    $self->{style} = $style;

    #
    ### prepare message processing
    #

    my ($encode, $decode)
      = $self->compileMessages(\%args, 'CLIENT', $soap);

    #
    ### prepare the transport
    #

    my $send = $args{transport};
    unless($send)
    {   my $impl = 'XML::Compile::Transport::SOAPHTTP';
 
        $proto eq SOAP11HTTP
           or error __x"only transport of HTTP implemented, not {protocol}"
                , protocol => $proto;

        # this is an optimization thing: often, the client and server will
        # be forking daemons: you do not want to load the module in each
        # child.  The users will immediately avoid this error.
        $impl->can('new')
            or error __x"explicitly put 'use {impl}' in your script"
                  , impl => $impl;

        my @endpoints = $args{endpoint_address} || $self->endPointAddresses;
        my $endpoints = join ';', @endpoints;
        my $transport = $self->{transporters}{$impl}{$endpoints}
                    ||= $impl->new(address => \@endpoints);

        $send = $transport->compileClient
          ( name     => $self->name
          , kind     => $self->kind
          , soap     => $version
          , action   => $self->soapAction
          , hook     => $args{transport_hook}
          );
    }

    $soap->compileClient
      ( name         => $self->name
      , kind         => $self->kind
      , encode       => $encode
      , decode       => $decode
      , transport    => $send
      , rpcout       => $args{rpcout}
      , rpcin        => $args{rpcin}
      );
}


sub compileHandler(@)
{   my ($self, %args) = @_;

    my $soap     = $args{soap};
    my $callback = $args{callback};

    my ($decode, $encode, $selector)
      = $self->compileMessages(\%args, 'SERVER', $soap);

    $soap->compileHandler
      ( name      => $self->name
      , kind      => $self->kind
      , selector  => $selector
      , encode    => $encode
      , decode    => $decode
      , callback  => $callback
      );
}


sub canTransport($$)
{   my ($self, $proto, $style) = @_;
    my $trans = $self->{trans};

    unless($trans)
    {   # collect the transport information
        my $soapns   = $self->soapNameSpace;
        my $bindtype = pack_type $soapns, 'binding';

        my $bindxml  = $self->binding->{$bindtype}
            or error __x"soap transport binding not found in binding";

        my $bind_r   = $self->schemas->compile(READER => $bindtype);
        my @bindings = map { $bind_r->($_) } @$bindxml;
  
        $_->{style} ||= 'document' for @bindings;
        my %bindings;
        push @{$bindings{$_->{transport}}{$_->{style}}}, $_ for @bindings;
        $self->{trans} = $trans = \%bindings;
    }

    $trans->{$proto}{$style};
}


sub compileMessages($$$)
{   my ($self, $args, $role, $soap) = @_;
    my $port   = $self->portOperation;
    my $bind   = $self->bindOperation;

    my ($output_parts, $output_enc)
     = $self->collectMessageParts($args, $port->{output},$bind->{output});

    my ($input_parts,  $input_enc)
     = $self->collectMessageParts($args, $port->{input}, $bind->{input});

    my ($fault_parts,  $fault_enc)
     = $self->collectFaultParts  ($args, $port->{fault}, $bind->{fault});

    # encodings is not supported by ::SOAP anymore, because there may
    # only be one part only in rpc-encoded which is capable of it
    # my $encodings = { %$output_enc, %$input_enc, %$fault_enc };

    my $use_style = $self->soapStyle || 'document';
    $use_style .= '-' . $self->soapUse
        if $use_style eq 'rpc';

    my $input = $soap->compileMessage
      ( ($role eq 'CLIENT' ? 'SENDER' : 'RECEIVER')
      , %$input_parts,  %$fault_parts,
      , style => $use_style
      , %$args
      );

    my $output = $soap->compileMessage
      ( ($role eq 'CLIENT' ? 'RECEIVER' : 'SENDER')
      , %$output_parts, %$fault_parts
      , style => $use_style
      , %$args
      );

    my $filter = $role ne 'SERVER' ? undef
      : $soap->compileFilter(%$input_parts);

    ($input, $output, $filter);
}


sub collectMessageParts($$$)
{   my ($self, $args, $portop, $bind) = @_;

    defined $portop          # communication not in two directions
        or return ({}, {});

    my (%parts, %encodings);

    my $msgname  = $portop->{message}
        or error __x"no message name in portOperation";

    my $message  = $self->wsdl->find(message => $msgname)
        or error __x"cannot find message {name}", name => $msgname;
    my $soapns   = $self->soapNameSpace;

    if(my $bind_body = $bind->{"{$soapns}body"})
    {   my $body_reader = $self->schemas->compile(READER => "{$soapns}body");
        my $body = $body_reader->($bind_body->[0]);

        if(!defined $self->soapStyle || $self->soapStyle eq 'document')
        {   my $body_parts = $body->{parts} || [];
            $parts{body} = [$self->messageSelectParts($message, @$body_parts)];
        }
        else  # only for RPC?
        {   $self->soapUse($body->{use} || 'literal');  # correct default?
        }
    }

    if(my $bind_headers = $bind->{"{$soapns}header"})
    {   my $header_reader = $self->schemas->compile(READER=> "{$soapns}header");
        my @headers = map {$header_reader->($_)} @$bind_headers;

        foreach my $header (@headers)
        {   my $use = $header->{use}
                or error __x"message {name} header requires use attribute"
                     , name => $msgname;

            my $hmsgname = $header->{message}
                or error __x"message {name} header requires message attribute"
                     , name => $msgname;

            my $hmsg = $self->wsdl->find(message => $hmsgname)
                or error __x"cannot find header message {name}"
                     , name => $hmsgname;

            my $partname = $header->{part}
                or error __x"message {name} header requires part attribute"
                     , name => $msgname;

            $encodings{$partname} = $header;
            push @{$parts{header}}
              , $self->messageSelectParts($hmsg, $partname);

            foreach my $hf ( @{$header->{headerfault} || []} )
            {   my $hfmsg  = $self->wsdl->find(message => $hf->{message})
                   or error __x"cannot find headerfault message {name}"
                         , name => $hf->{message};
                my $hfname = $hf->{part};
                $encodings{$hfname} = $hf;
                push @{$parts{headerfault}}
                  , $self->messageSelectParts($hfmsg, $hfname);
            }

            $encodings{$partname} = $header;
        }
    }

    (\%parts, \%encodings);
}


sub messageSelectParts($@)
{   my ($self, $msg) = (shift, shift);
    my @parts = @{$msg->{part} || []};
    my @names = @_ ? @_ : map {$_->{name}} @parts;
    my %parts = map { ($_->{name} => $_) } @parts;
    my @sel;

    foreach my $name (@names)
    {   my $part = $parts{$name}
            or error __x"message {msg} does not have a part named {part}"
                  , msg => $msg->{name}, part => $name;

        my $element;
        if($element = $part->{element})
        {   # ok, simple case: follow the rules of the schema
        }
        elsif(my $type = $part->{type})
        {   # hum... no element but we need one... let's fake one
            # (but in which namespace?)  The element name might get
            # overwritten by the next compilation.
            # Profile says this is not permitted?
            my ($type_ns, $type_local) = unpack_type $type;
            $element = pack_type '', $name;
#warn "($type, $type_ns, $type_local, $element)";
            $self->schemas->importDefinitions( <<__FAKE_ELEMENT );
<schema xmlns:xx="$type_ns">
  <element name="$name" type="xx:$type_local" />
</schema>
__FAKE_ELEMENT
        }
        else
        {   error __x"part {name} has neighter element nor type", name=>$name;
        }

        push @sel, $name => $element;
    }

    @sel;
}


sub collectFaultParts($$$)
{   my ($self, $args, $portop, $bind) = @_;
    my (%parts, %encodings);

    my $soapns       = $self->soapNameSpace;
    my $bind_faults  = $bind->{"{$soapns}fault"}
        or return ({}, {});

    my $port_faults  = $portop->{fault} || [];
    my $fault_reader = $self->schemas->compile(READER => "{$soapns}fault");

    foreach my $bind_fault (@$bind_faults)
    {   my $fault = ($fault_reader->($bind_fault))[1];
        my $name  = $fault->{name};

        my $port  = first {$_->{name} eq $name} @$port_faults;
        defined $port
            or error __x"cannot find port for fault {name}", name => $name;

        my $msgname = $port->{message}
            or error __x"no fault message name in portOperation";

        my $message = $self->wsdl->find(message => $msgname)
            or error __x"cannot find fault message {name}", name => $msgname;

        defined $message->{parts} && @{$message->{parts}}==1
            or error __x"fault message {name} must have one part exactly"
                  , name => $msgname;
        my $part    = $message->{parts}[0];

        push @{$parts{fault}}, $name => $part;
        $encodings{$name} = $part;
    }

    (\%parts, \%encodings);
}

1;
