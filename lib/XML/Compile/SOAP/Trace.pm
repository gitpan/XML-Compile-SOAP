# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package XML::Compile::SOAP::Trace;
use vars '$VERSION';
$VERSION = '0.78';


use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub new($)
{   my ($class, $data) = @_;
    bless $data, $class;
}


sub start() {shift->{start}}


sub date() {scalar localtime shift->start}


sub elapse($)
{   my ($self, $kind) = @_;
    defined $kind ? $self->{$kind.'_elapse'} : $self->{elapse};
}


sub request() {shift->{http_request}}


sub response() {shift->{http_response}}


sub printTimings()
{   my $self = shift;
    print  "Call initiated at: ",$self->date, "\n";
    print  "SOAP call timing:\n";
    printf "      encoding: %7.2f ms\n", $self->elapse('encode')    *1000;
    printf "     stringify: %7.2f ms\n", $self->elapse('stringify') *1000;
    printf "    connection: %7.2f ms\n", $self->elapse('connect')   *1000;
    printf "       parsing: %7.2f ms\n", $self->elapse('parse')     *1000;

    my $dt = $self->elapse('decode');
    if(defined $dt) { printf "      decoding: %7.2f ms\n", $dt *1000 }
    else            { print  "      decoding:       -    (no xml answer)\n" }

    printf "    total time: %7.2f ms ",  $self->elapse              *1000;
    printf "= %.3f seconds\n\n", $self->elapse;
}


sub printRequest(@)
{   my $self = shift;
    my $request = $self->request or return;
    my $req  = $request->as_string;
    $req =~ s/^/  /gm;
    print "Request:\n$req\n";
}


sub printResponse(@)
{   my $self = shift;
    my $response = $self->response or return;

    my $resp = $response->as_string;
    $resp =~ s/^/  /gm;
    print "Response:\n$resp\n";
}

1;
