# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Trace;
use vars '$VERSION';
$VERSION = '2.21';


use Log::Report 'xml-compile-soap', syntax => 'REPORT';
  # no syntax SHORT, because we have own error()

use IO::Handle;


sub new($)
{   my ($class, $data) = @_;
    bless $data, $class;
}


sub start() {shift->{start}}


sub date() {scalar localtime shift->start}


sub error() {shift->{error}}


sub elapse($)
{   my ($self, $kind) = @_;
    defined $kind ? $self->{$kind.'_elapse'} : $self->{elapse};
}


sub request() {shift->{http_request}}


sub response() {shift->{http_response}}


sub printTimings(;$)
{   my ($self, $fh) = @_;
    my $oldfh = $fh ? (select $fh) : undef;
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
    select $oldfh if $oldfh;
}


sub printRequest(;$)
{   my ($self, $fh) = @_;
    my $request = $self->request or return;
    my $req     = $request->as_string;
    $req =~ s/^/  /gm;
    ($fh || *STDOUT)->print("Request:\n$req\n");
}


sub printResponse(;$)
{   my ($self, $fh) = @_;
    my $response = $self->response or return;
    my $resp     = $response->as_string;
    $resp =~ s/^/  /gm;
    ($fh || *STDOUT)->print("Response:\n$resp\n");
}

1;
