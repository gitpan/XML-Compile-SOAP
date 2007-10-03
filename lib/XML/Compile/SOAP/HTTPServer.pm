# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP::HTTPServer;
use vars '$VERSION';
$VERSION = '0.55';
use base 'XML::Compile::SOAP::Server', 'HTTP::Daemon';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Util    qw/pack_type/;

use XML::LibXML    ();
use LWP            ();
use LWP::UserAgent ();
use HTTP::Response ();
use Time::HiRes   qw/time/;
use List::Util    qw/first/;

# (Microsofts HTTP Extension Framework)
my $http_ext_id = 'http://schemas.xmlsoap.org/soap/envelope/';


sub new(@)
{   my ($class, %args) = @_;
    my %opts;   # all options which are not for the daemon must be collected

    my $self = delete $args{daemon} || HTTP::Daemon->new(%args);
    bless $self, $class;   # upgrade

    $self->init(%opts);
}

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $support = delete $args->{support_soap} || 'ANY';

    if($support eq 'ANY' || $support eq 'SOAP11')
    {   require XML::Compile::SOAP11;
        my $soap11 = $self->{version_SOAP11} = XML::Compile::SOAP11->new;
        $soap11->prepareServer($self);
    }

    if($support eq 'ANY' || $support eq 'SOAP12')
    {   require XML::Compile::SOAP12;
        my $soap12 = $self->{version_SOAP12} = XML::Compile::SOAP12->new;
        $soap12->prepareServer($self);
    }
    $self;
}


sub soapImplementation($)
{   my ($self, $version) = @_;
    $self->{"version_$version"};
}


my $parser = XML::LibXML->new;
sub run(@)
{   my ($self, %args) = @_;

    my $soap11 = $self->soapImplementation('SOAP11');
    my $soap12 = $self->soapImplementation('SOAP12');

  CONNECTION:
    while(my $connection = $self->accept)
    {
      REQUEST:
        while(my($request, $peer) = $connection->get_request)
        {   my $media  = $request->content_type || 'text/plain';
            unless($media =~ m![/+]xml$!i)
            {   info __x"request from {client} request not xml but {media}"
                  , client => $peer, media => $media;
                next REQUEST;
            }

            my $action = $self->getSoapAction($request);

            unless(defined $action)
            {   info __x"request from {client} request not soap"
                  , client => $peer;
                next REQUEST;
            }

            my $ct = $request->header('Content-Type');
            my $charset = $ct =~ m/\;\s*type\=(["']?)([\w-]*)\1/ ? $2:'utf-8';
            
            my $input = try { $parser->parse_string
              ($request->decoded_content(charset => $charset)) };
            if($@ || !$input)
            {   info __x"request from {client}, {action} parse error {msg}"
                    , client => $peer, action => $action, msg => $@;
### give parse failure as answer
                next REQUEST;
            }

            my $env = $input->namespaceURI || '';
            my ($soap, $soap_version)
              = $soap11 && $soap11->envelopeNS eq $env ? ($soap11, 'SOAP11')
              : $soap12 && $soap12->envelopeNS eq $env ? ($soap12, 'SOAP12')
              : undef;
            unless($soap_version)
            {   alert __x"request from {client} for {action} with unknown envelope {type}"
                    , client => $peer, action => $action, type => $env;
                next REQUEST;
            }

            my ($decode, $encode, $callback)
               = $self->actionHandler($action, $soap_version);

            if(   !defined $decode
               && $soap_version eq 'SOAP12'
               && $self->actionHandler($action, 'SOAP11'))
            {   
### give downgrade answer
                next REQUEST;
            }

            unless(defined $decode)
            {   info __x"request from {client} requests unknown {action}"
                  , client => $peer, action => $action;
### give 'unknown' as answer
                next REQUEST;
            }

            my $query = try { $decode->($input) };
            if($@)
            {    info __x"request from {client}, {action} type error  {msg}"
                    , client => $peer, action => $action, msg => $@;
### give interpretation failure as answer
                 next REQUEST
            }

            info __x"request from {client} request {soap} {action}"
              , client => $peer, soap => $soap_version, action => $action;

            my $answer = try { $callback->($query, $self) };
            if($@)
            {   alert __x"request action {action} callback failed: {msg}"
                   , action => $action, msg => $@;
### give internal server error
                 next REQUEST
            }

            my $output = try { $encode->($answer, $soap_version) };
            if($@)
            {   alert __x"request action {action} encoding failed: {msg}"
                   , action => $action, msg => $@;
### give internal server error
                 next REQUEST
            }

            my $response = HTTP::Response->new(200 => 'OK');
            $response->content($response->toString);

            if(substr($request->method, 0, 2) eq 'M-')
            {   # HTTP extension framework.  More needed?
                $response->header(Ext => '');
            }

            $connection->send_response($response);
        }
    }
}


sub getSoapAction($)
{   my ($self, $request) = @_;

    my $action;
    if($request->method eq 'POST')
    {   $action = $request->header('SOAPAction');
    }
    elsif($request->method eq 'M-POST')
    {   my $man = first {$_ =~ m/\"$http_ext_id\"/} $request->header('Man');
        defined $man or return undef;

        $man =~ m/\;\s*ns\=(\d+)/ or return undef;
        $action = $request->header("$1-SOAPAction");
    }
    else
    {   return undef;
    }

      !defined $action            ? undef
    : $action =~ m/^\s*\"(.*?)\"/ ? $1
    :                               '';
}


sub actionHandler($$;$$$)
{   my ($self, $action, $version) = (shift, shift, shift);
    my $def = $self->{"handler_$version"}{$action};
    @_  or return $def ? @$def : ();

    # ignore unsupported protocols
    $self->soapImplementation($version)
        or return ();

    $self->{"handler_$version"}{$action} = [ @_ ];
    @_;
}

1;
