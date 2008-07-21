# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package XML::Compile::WSDL11;
use vars '$VERSION';
$VERSION = '0.75';

use base 'XML::Compile';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Schema  ();
use XML::Compile::SOAP    ();
use XML::Compile::Util    qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;

use XML::Compile::WSDL11::Operation ();

use List::Util  qw/first/;
use Data::Dumper;  # needs to go away

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( &WSDL11       => 'wsdl.xsd'
 , &WSDL11SOAP   => 'wsdl-soap.xsd'
 , &WSDL11HTTP   => 'wsdl-http.xsd'
 , &WSDL11MIME   => 'wsdl-mime.xsd'
 , &WSDL11SOAP12 => 'wsdl-soap12.xsd'
 );


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{schemas} = $args->{schemas} || XML::Compile::Schema->new;
    $self->{index}   = {};
    $self->{wsdl_ns} = $args->{wsdl_namespace};

    $self->addWSDL($args->{top});
    $self;
}


sub schemas() { shift->{schemas} }


sub wsdlNamespace(;$)
{   my $self = shift;
    @_ ? ($self->{wsdl_ns} = shift) : $self->{wsdl_ns};
}


sub addWSDL($)
{   my ($self, $data) = @_;

    defined $data or return;
    my ($node, %details) = $self->dataToXML($data)
        or return $self;

    my $schemas = $self->schemas;

    # Collect the user schema

    $node    = $node->documentElement
        if $node->isa('XML::LibXML::Document');

    $node->localName eq 'definitions'
        or error __x"root element for WSDL is not 'definitions'";

    $schemas->importDefinitions($node, details => \%details);

    # Collect the WSDL schemata

    my $wsdlns  = $node->namespaceURI;
    my $corens  = $self->wsdlNamespace || $self->wsdlNamespace($wsdlns);

    $corens eq $wsdlns
        or error __x"wsdl in namespace {wsdlns}, where already using {ns}"
               , wsdlns => $wsdlns, ns => $corens;

    $wsdlns eq WSDL11
        or error __x"don't known how to handle {wsdlns} WSDL files"
               , wsdlns => $wsdlns;

    $schemas->importDefinitions($wsdlns, %details);

    my %hook_kind =
     ( type         => pack_type($wsdlns, 'tOperation')
     , after        => 'ELEMENT_ORDER'
     );

    my $reader    = $schemas->compile        # to parse the WSDL
     ( READER       => pack_type($wsdlns, 'definitions')
     , anyElement   => 'TAKE_ALL'
     , anyAttribute => 'TAKE_ALL'
     , hook         => \%hook_kind
     );

    my $spec = $reader->($node);
    my $tns  = $spec->{targetNamespace}
        or error __x"WSDL sets no targetNamespace";

    # WSDL 1.1 par 2.1.1 says: WSDL def types each in own name-space
    my $index     = $self->{index};
    my $toplevels = $spec->{gr_import} || [];  # silly WSDL structure
    foreach my $toplevel (@$toplevels)
    {   my ($which, $def) = %$toplevel;        # always only one
        $index->{$which}{pack_type $tns, $def->{name}} = $def
            if $which =~ m/^(?:service|message|binding|portType)$/;
    }

    foreach my $service ( @{$spec->{service} || []} )
    {   foreach my $port ( @{$service->{port} || []} )
        {   $index->{port}{pack_type $tns, $port->{name}} = $port;
        }
    }

    $self;
}


sub importDefinitions($@) { shift->schemas->importDefinitions(@_) }


sub namesFor($)
{   my ($self, $class) = @_;
    keys %{shift->index($class) || {}};
}


# new options, then also add them to the list in compileClient()

sub operation(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = @_;

    my $service   = $self->find(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{port} || []};
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

    my $bindname  = $port->{binding}
        or error __x"no binding defined in port '{name}'"
               , name => $port->{name};

    my $binding   = $self->find(binding => $bindname);

    my $type      = $binding->{type}
        or error __x"no type defined with binding `{name}'"
               , name => $bindname;

    my $portType  = $self->find(portType => $type);
    my $types     = $portType->{operation}
        or error __x"no operations defined for portType `{name}'"
               , name => $type;

    my @port_ops  = map {$_->{name}} @$types;

    $name       ||= delete $args{operation};
    my $port_op;
    if(defined $name)
    {   $port_op = first {$_->{name} eq $name} @$types;
        error __x"no operation `{operation}' for portType {porttype}, pick from{ops}"
            , operation => $name
            , porttype => $type
            , ops => join("\n    ", '', @port_ops)
            unless $port_op;
    }
    elsif(@port_ops==1)
    {   $port_op = shift @port_ops;
    }
    else
    {   error __x"multiple operations in portType `{porttype}', pick from {ops}"
            , porttype => $type
            , ops => join("\n    ", '', @port_ops)
    }

    my @bindops = @{$binding->{operation} || []};
    my $bind_op = first {$_->{name} eq $name} @bindops;

    my $operation = XML::Compile::WSDL11::Operation->new
     ( service  => $service
     , port     => $port
     , binding  => $binding
     , portType => $portType
     , wsdl     => $self
     , port_op  => $port_op
     , bind_op  => $bind_op
     , name     => $name
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


sub find($;$)
{   my ($self, $class, $name) = @_;
    my $group = $self->index($class)
        or error __x"no definitions for `{class}' found", class => $class;

    if(defined $name)
    {   return $group->{$name} if exists $group->{$name};
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
    my $produce = delete $args{produce} || 'HASHES';

  SERVICE:
    foreach my $service ($self->find('service'))
    {
      PORT:
        foreach my $port (@{$service->{port} || []})
        {
            my $bindname = $port->{binding}
                or error __x"no binding defined in port '{name}'"
                      , name => $port->{name};
            my $binding  = $self->find(binding => $bindname);

            my $type     = $binding->{type}
                or error __x"no type defined with binding `{name}'"
                    , name => $bindname;
            my $portType = $self->find(portType => $type);
            my $types    = $portType->{operation}
                or error __x"no operations defined for portType `{name}'"
                     , name => $type;

            if($produce ne 'OBJECTS')
            {   foreach my $operation (@$types)
                {   push @ops
                      , { service   => $service->{name}
                        , port      => $port->{name}
                        , portType  => $portType->{name}
                        , binding   => $bindname
                        , operation => $operation->{name}
                        };
                }
                next PORT;
            }
 
            foreach my $operation (@$types)
            {   my @bindops = @{$binding->{operation} || []};
                my $op_name = $operation->{name};
                my $bind_op = first {$_->{name} eq $op_name} @bindops;

                push @ops, XML::Compile::WSDL11::Operation->new
                  ( name      => $operation->{name}
                  , service   => $service
                  , port      => $port
                  , portType  => $portType
                  , binding   => $binding
                  , wsdl      => $self
                  , port_op   => $operation
                  , bind_op   => $bind_op
                  );
            }
        }
    }

    @ops;
}

#--------------------------------



1;
