# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package XML::Compile::WSDL11;
use vars '$VERSION';
$VERSION = '2.00_01';

use base 'XML::Compile::Cache';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11 SOAP11ENV/;

#use XML::Compile::SOAP11::Operation   ();
#use XML::Compile::Transport::SOAPHTTP ();
use XML::Compile::Operation  ();
use XML::Compile::Transport  ();

use List::Util  qw/first/;

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
  ( &WSDL11       => 'wsdl.xsd'
  , &WSDL11HTTP   => 'wsdl-http.xsd'
  );


sub init($)
{   my ($self, $args) = @_;
    $args->{schemas} and panic "new(schemas) option removed in 0.78";
    my $wsdl = delete $args->{top};

    local $args->{any_element}      = 'ATTEMPT';
    local $args->{any_attribute}    = 'ATTEMPT';
    local $args->{allow_undeclared} = 1;

    $self->SUPER::init($args);

    $self->{index}   = {};

    $self->prefixes(wsdl => WSDL11, soap => WSDL11SOAP, http => WSDL11HTTP);
    $self->importDefinitions(WSDL11);

    $_->can('_initWSDL11') && $_->_initWSDL11($self)
        for XML::Compile::Operation->registered
          , XML::Compile::Transport->registered;

    $self->declare
     ( READER       => 'wsdl:definitions'
     , key_rewrite  => 'PREFIXED'
     , hook         =>
        { type =>  'wsdl:tOperation'
        , after => 'ELEMENT_ORDER'
        }
     );

    $self->addWSDL($wsdl);
    $self;
}

sub schemas(@) { panic "schemas() removed in v2.00, not needed anymore" }

#--------------------------


sub _learn_prefixes($)
{   my ($self, $node) = @_;

    my $namespaces = $self->prefixes;
  PREFIX:
    foreach my $ns ($node->getNamespaces)  # learn preferred ns
    {   my ($prefix, $uri) = ($ns->getLocalName, $ns->getData);
        next if !defined $prefix || $namespaces->{$uri};

        if(my $def = $self->prefix($prefix))
        {   next PREFIX if $def->{uri} eq $uri;
        }
        else
        {   $self->prefixes($prefix => $uri);
            next PREFIX;
        }

        $prefix =~ s/0?$/0/;
        while(my $def = $self->prefix($prefix))
        {   next PREFIX if $def->{uri} eq $uri;
            $prefix++;
        }
        $self->prefixes($prefix => $uri);
    }
}

sub addWSDL($)
{   my ($self, $data) = @_;
    defined $data or return ();

    defined $data or return;
    my ($node, %details) = $self->dataToXML($data);
    defined $node or return $self;

    $node->localName eq 'definitions' && $node->namespaceURI eq WSDL11
        or error __x"root element for WSDL is not 'wsdl:definitions'";

    $self->importDefinitions($node, details => \%details);
    $self->_learn_prefixes($node);

    my $spec = $self->reader('wsdl:definitions')->($node);
    my $tns  = $spec->{targetNamespace}
        or error __x"WSDL sets no targetNamespace";

    # WSDL 1.1 par 2.1.1 says: WSDL def types each in own name-space
    my $index     = $self->{index};

    # silly WSDL structure
    my $toplevels = $spec->{gr_wsdl_anyTopLevelOptionalElement} || [];

    foreach my $toplevel (@$toplevels)
    {   my ($which, $def) = %$toplevel;        # always only one
        $which =~ s/^wsdl_(service|message|binding|portType)$/$1/
            or next;

        $index->{$which}{pack_type $tns, $def->{name}} = $def;

        if($which eq 'service')
        {   foreach my $port ( @{$def->{port} || []} )
            {   $index->{port}{pack_type $tns, $port->{name}} = $port;
            }
        }
    }

#warn "INDEX: ",Dumper $index;
    $self;
}


sub namesFor($)
{   my ($self, $class) = @_;
    keys %{shift->index($class) || {}};
}


# new options, then also add them to the list in compileClient()

sub operation(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = (name => $name, @_);

    #
    ## Service structure
    #

    my $service   = $self->findDef(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{wsdl_port} || []};
    my @portnames = map {$_->{name}} @ports;
    if(my $portname = delete $args{port})
    {   $port = first {$_->{name} eq $portname} @ports;
        error __x"cannot find port `{portname}', pick from {ports}"
            , portname => $portname, ports => join("\n    ", '', @portnames)
           unless $port;
    }
    elsif(@ports==1)
    {   $port = shift @ports;
    }
    else
    {   error __x"specify port explicitly, pick from {portnames}"
            , portnames => join("\n    ", '', @portnames);
    }

    # get plugin for operation

    my $address   = first { $_ =~ m/[_}]address$/ } keys %$port
        or error __x"no address provided in service port";

    if($address =~ m/^{/)
    {   my ($ns)  = unpack_type $address;

        warning __"Since v2.00 you have to require XML::Compile::SOAP11 explicitly"
            if $ns eq WSDL11SOAP;

        error __x"ports of type {ns} not supported (not loaded?)", ns => $ns;
    }

    my ($prefix)  = $address =~ m/(\w+)_address$/;
    my $opns      = $self->findName("$prefix:");
    my $opclass   = XML::Compile::Operation->plugin($opns);
    $opclass->can('_fromWSDL11')
        or error __x"WSDL11 not supported by {class}", class => $opclass;

    #
    ## Binding
    #

    my $bindname  = $port->{binding}
        or error __x"no binding defined in port '{name}'"
               , name => $port->{name};

    my $binding   = $self->findDef(binding => $bindname);

    my $type      = $binding->{type}
        or error __x"no type defined with binding `{name}'"
               , name => $bindname;

    my $portType  = $self->findDef(portType => $type);
    my $types     = $portType->{wsdl_operation}
        or error __x"no operations defined for portType `{name}'"
               , name => $type;

    my @port_ops  = map {$_->{name}} @$types;

    $name       ||= delete $args{operation};
    my $port_op;
    if(defined $name)
    {   $port_op = first {$_->{name} eq $name} @$types;
        error __x"no operation `{op}' for portType {pt}, pick from{ops}"
          , op => $name, pt => $type, ops => join("\n    ", '', @port_ops)
            unless $port_op;
    }
    elsif(@port_ops==1)
    {   $port_op = shift @port_ops;
    }
    else
    {   error __x"multiple operations in portType `{pt}', pick from {ops}"
            , pt => $type, ops => join("\n    ", '', @port_ops)
    }

    my @bindops   = @{$binding->{wsdl_operation} || []};
    my $bind_op   = first {$_->{name} eq $name} @bindops;

    # This should be detected while parsing the WSDL because the order of
    # input and output is significant (and lost), but WSDL 1.1 simplifies
    # our life by saying that only 2 out-of 4 predefined types can actually
    # be used at present.

    my @order = map { (unpack_type $_)[1] } @{$port_op->{_ELEMENT_ORDER}};

    my ($first_in, $first_out);
    for(my $i = 0; $i<@order; $i++)
    {   $first_in  = $i if !defined $first_in  && $order[$i] eq 'input';
        $first_out = $i if !defined $first_out && $order[$i] eq 'output';
    }

    my $kind
      = !defined $first_in     ? 'notification-operation'
      : !defined $first_out    ? 'one-way'
      : $first_in < $first_out ? 'request-response'
      :                          'solicit-response';

    #
    ### message components
    #

    my $operation = $opclass->_fromWSDL11
     ( name      => $name,
     , kind      => $kind

     , service   => $service
     , serv_port => $port
     , binding   => $binding
     , bind_op   => $bind_op
     , portType  => $portType
     , port_op   => $port_op

     , wsdl      => $self
     );

    $operation;
}


sub compileClient(@)
{   my $self = shift;
    unshift @_, 'operation' if @_ % 2;
    my $op   = $self->operation(@_) or return ();
    $op->compileClient(@_);
}

#---------------------


sub index(;$$)
{   my $index = shift->{index};
    @_ or return $index;

    my $class = $index->{ (shift) }
       or return ();

    @_ ? $class->{ (shift) } : $class;
}


sub findDef($;$)
{   my ($self, $class, $name) = @_;
    my $group = $self->index($class)
        or error __x"no definitions for `{class}' found", class => $class;

    if(defined $name)
    {   return $group->{$name} if exists $group->{$name};

        if(my $q = first { (unpack_type $_)[1] eq $name } keys %$group)
        {   return $group->{$q};
        }

        error __x"no definition for `{name}' as {class}, pick from:{groups}"
          , name => $name, class => $class
          , groups => join("\n    ", '', sort keys %$group);
    }

    return values %$group
        if wantarray;

    return (values %$group)[0]
        if keys %$group==1;

    error __x"explicit selection required: pick one {class} from {groups}"
      , class => $class, groups => join("\n    ", '', sort keys %$group);
}


sub operations(@)
{   my ($self, %args) = @_;
    my @ops;
    $args{produce} and die "produce option removed in 0.81";

    foreach my $service ($self->findDef('service'))
    {
        foreach my $port (@{$service->{wsdl_port} || []})
        {
            my $bindname = $port->{binding}
                or error __x"no binding defined in port '{name}'"
                      , name => $port->{name};
            my $binding  = $self->findDef(binding => $bindname);

            my $type     = $binding->{type}
                or error __x"no type defined with binding `{name}'"
                    , name => $bindname;

            foreach my $operation ( @{$binding->{wsdl_operation}||[]} )
            {   push @ops, $self->operation
                  ( service   => $service->{name}
                  , port      => $port->{name}
                  , binding   => $bindname
                  , operation => $operation->{name}
                  , portType  => $type
                  );
            }
        }
    }

    @ops;
}

#--------------------------------



1;
