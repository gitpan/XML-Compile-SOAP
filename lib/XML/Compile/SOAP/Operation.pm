# Copyrights 2007-2014 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.
use warnings;
use strict;

package XML::Compile::SOAP::Operation;
use vars '$VERSION';
$VERSION = '3.01';


use Log::Report 'xml-report-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;


sub new(@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{kind}     = $args->{kind} or die;
    $self->{name}     = $args->{name} or die;
    $self->{schemas}  = $args->{schemas} or die;

    $self->{transport} = $args->{transport};
    $self->{action}   = $args->{action};

    my $ep = $args->{endpoints} || [];
    my @ep = ref $ep eq 'ARRAY' ? @$ep : $ep;
    $self->{endpoints} = \@ep;

    # undocumented, because not for end-user
    if(my $binding = $args->{binding})  { $self->{bindname} = $binding->{name} }
    if(my $service = $args->{service})  { $self->{servname} = $service->{name} }
    if(my $port    = $args->{serv_port}){ $self->{portname} = $port->{name} }
    if(my $port_type= $args->{portType}){ $self->{porttypename} = $port_type->{name} }

    $self;
}


sub schemas()   {shift->{schemas}}
sub kind()      {shift->{kind}}
sub name()      {shift->{name}}
sub style()     {shift->{style}}
sub transport() {shift->{transport}}
sub version()   {panic}

sub bindingName() {shift->{bindname}}
sub serviceName() {shift->{servname}}
sub portName()    {shift->{portname}}
sub portTypeName(){shift->{porttypename}}


sub soapAction  {shift->{action}}
sub action()    {shift->{action}} # deprecated

# wsaAction is implement in XML::Compile::SOAP::WSA


sub serverClass {panic}
sub clientClass {panic}


sub endPoints() { @{shift->{endpoints}} }

#-------------------------------------------


sub compileTransporter(@)
{   my ($self, %args) = @_;

    my $send      = delete $args{transporter} || delete $args{transport};
    return $send if $send;

    my $proto     = $self->transport;
    my @endpoints;
    if(my $endpoints = $args{endpoint})
    {   @endpoints = ref $endpoints eq 'ARRAY' ? @$endpoints : $endpoints;
    }
    unless(@endpoints)
    {   @endpoints = $self->endPoints;
        if(my $s = $args{server})
        {   s#^(\w+)://([^/]+)#$1://$s# for @endpoints;
        }
    }

    my $id        = join ';', sort @endpoints;
    $send         = $self->{transp_cache}{$proto}{$id};
    return $send if $send;

    my $transp    = XML::Compile::Transport->plugin($proto)
        or error __x"transporter type {proto} not supported (add 'use {pkg}'?)"
             , proto => $proto, pkg => 'XML::Compile::Transport::SOAPHTTP';

    my $transport = $self->{transp_cache}{$proto}{$id}
                  = $transp->new(address => \@endpoints, %args);

    $transport->compileClient
      ( name     => $self->name
      , kind     => $self->kind
      , action   => $self->action
      , hook     => $args{transport_hook}
      , %args
      );
}


sub compileClient(@)  { panic "not implemented" }
sub compileHandler(@) { panic "not implemented" }


sub explain($$$@)
{   my ($self, $wsdl, $format, $dir, %args) = @_;
    panic "not implemented for ".ref $self;
}

1;
