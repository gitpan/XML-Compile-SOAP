# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package XML::Compile::Operation;
use vars '$VERSION';
$VERSION = '2.00_01';


use Log::Report 'xml-report-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;


sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

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

    $self;
}


sub schemas()   {shift->{schemas}}
sub kind()      {shift->{kind}}
sub name()      {shift->{name}}
sub action()    {shift->{action}}
sub style()     {shift->{style}}
sub transport() {shift->{transport}}


sub endPoints() { @{shift->{endpoints}} }

#-------------------------------------------


sub compileTransporter(@)
{   my ($self, %args) = @_;

    my $send      = $args{transporter};
    return $send if $send;

    my $proto     = $self->transport;
    my @endpoints = $args{endpoint} || $self->endPoints;
    my $id        = join ';', sort @endpoints;
    $send         = $self->{transp_cache}{$proto}{$id};
    return $send if $send;

    my $transp    = XML::Compile::Transport->plugin($proto)
        or error __x"transporter type {proto} not supported (not loaded?)"
             , proto => $proto;

    my $transport = $self->{transp_cache}{$proto}{$id}
                  = $transp->new(address => \@endpoints);

    $transport->compileClient
      ( name     => $self->name
      , kind     => $self->kind
      , action   => $self->action
      , hook     => $args{transport_hook}
      );
}


sub compileClient(@)  { panic "not implemented" }
sub compileHandler(@) { panic "not implemented" }


{   my %registered;
    sub register($)   { my ($class, $uri) = @_; $registered{$uri} = $class }
    sub plugin($)     { my ($class, $uri) = @_; $registered{$uri} }
    sub registered($) { values %registered }
}

1;
