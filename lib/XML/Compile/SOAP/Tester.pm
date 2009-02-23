# Copyrights 2007-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Tester;
use vars '$VERSION';
$VERSION = '2.02';


use XML::Compile::SOAP::Client ();

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use Time::HiRes   qw/time/;


sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init()
{   my ($self, $args) = @_;

    # just like XML::Compile::SOAP::Server is doing it
    if(my $cb = delete $args->{callbacks})
    {   my ($version, $data) = ref $cb eq 'ARRAY' ? @$cb : (ANY => $cb);
        while(my ($action, $code) = each %$data)
        {   $self->actionCallback($action, $code, $version);
        }
    }

    XML::Compile::SOAP::Client->fakeServer($self);
}

#------------------------------------------------


# code equivalent to method in XML::Compile::SOAP::Server
sub actionCallback($$;$)
{   my ($self, $action, $code, $soap) = @_;
    my $version = !defined $soap ? undef : ref $soap ? $soap->version : $soap;
    undef $version if $version eq 'ANY';
    foreach my $v ('SOAP11', 'SOAP12')
    {   next if defined $version && $version ne $v;
        $self->{actions}{$v}{$action}{callback} = $code
           if exists $self->{actions}{$v}{$action};
    }
}

#------------------------------------------------


sub request(@)
{   my ($self,%trace) = @_;
    my $action  = $trace{action};
    my $version = $trace{soap_version};
    my $cb      = $self->{actions}{$version}{$action};

    unless($cb)
    {   notice __x"cannot find action {action} for {soap}"
          , action => $action, soap => $version;
        return (undef, \%trace);
    }

    my $answer  = $cb->($trace{message});
    ($answer, \%trace);
}

1;
