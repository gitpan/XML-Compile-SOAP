# Copyrights 2007-2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP11;
use vars '$VERSION';
$VERSION = '2.28';

use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util       qw/pack_type unpack_type SCHEMA2001/;
use XML::Compile::SOAP::Util qw/:soap11/;

# publish interface to WSDL
use XML::Compile::SOAP11::Operation ();

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( &SOAP11ENC => 'soap-encoding.xsd'
 , &SOAP11ENV => 'soap-envelope.xsd'
 );


sub new($@)
{   my $class = shift;
    $class ne __PACKAGE__
        or error __x"only instantiate a SOAP11::Client or ::Server";
    $class->SUPER::new(@_);
}

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->_initSOAP11($self->schemas);
}

sub _initSOAP11($)
{   my ($self, $schemas) = @_;
    return $self
        if $schemas->{did_init_SOAP11}++;   # ugly

    $schemas->importDefinitions
      ( [SOAP11ENC, SOAP11ENV]
      , element_form_default   => 'qualified'
      , attribute_form_default => 'qualified'
      );
    $schemas->importDefinitions('soap-envelope-patch.xsd');

    $schemas->prefixes
      ( 'SOAP-ENV' => SOAP11ENV  # preferred names by spec
      , 'SOAP-ENC' => SOAP11ENC
      , xsd        => SCHEMA2001
      );

    $self;
}

sub version    { 'SOAP11' }
sub envelopeNS { SOAP11ENV }

#-----------------------------------


sub compileMessage($$)
{   my ($self, $direction, %args) = @_;
    $args{style}    ||= 'document';

    if(ref $args{body} eq 'ARRAY')
    {   my @h = @{$args{body}};
        my @parts;
        push @parts, { name => shift @h, element => shift @h } while @h;
        $args{body} = {use => 'literal', parts => \@parts};
    }

    if(ref $args{header} eq 'ARRAY')
    {   my @h = @{$args{header}};
        my @o;
        while(@h)
        {  my $part = { name => shift @h, element => shift @h };
           push @o, {use => 'literal', parts => [ $part ]};
        }
        $args{header} = \@o;
    }

    my $f = $args{faults};
    if(ref $f eq 'ARRAY')
    {   $args{faults} = {};
        my @f = @$f;
        while(@f)
        {   my $name = shift @f;
            my $part = { name => $name, element => shift @f };
            $args{faults}{$name} = { use => 'literal', part => $part };
        }
    }

    $self->SUPER::compileMessage($direction, %args);
}

#------------------------------------------------
# Sender

sub _envNS { SOAP11ENV }

sub _sender(@)
{   my ($self, %args) = @_;

    ### merge info into headers
    # do not destroy original of args
    my %destination = @{$args{destination} || []};

    my $understand  = $args{mustUnderstand};
    my %understand  = map { ($_ => 1) }
        ref $understand eq 'ARRAY' ? @$understand
      : defined $understand ? $understand : ();

    foreach my $h ( @{$args{header} || []} )
    {   my $part  = $h->{parts}[0];
        my $label = $part->{name};
        $part->{mustUnderstand} ||= delete $understand{$label};
        $part->{destination}    ||= delete $destination{$label};
    }

    if(keys %understand)
    {   error __x"mustUnderstand for unknown header {headers}"
          , headers => [keys %understand];
    }

    if(keys %destination)
    {   error __x"destination for unknown header {headers}"
          , headers => [keys %destination];
    }

    # faults are always possible
    my @bparts  = @{$args{body}{parts} || []};
    my $w = $self->schemas->writer('SOAP-ENV:Fault'
      , include_namespaces => sub {$_[0] ne SOAP11ENV && $_[2]}
      );
    push @bparts,
      { name    => 'Fault'
      , element => pack_type(SOAP11ENV, 'Fault')
      , writer  => $w
      };
    local $args{body}{parts} = \@bparts;

    $self->SUPER::_sender(%args);
}

sub _writer_header($)
{   my ($self, $args) = @_;
    my ($rules, $hlabels) = $self->SUPER::_writer_header($args);

    my $header = $args->{header};
    my @rules;
    foreach my $h (@{$header || []})
    {   my $part  = $h->{parts}[0];
        my $label = $part->{name};
        $label eq shift @$rules or panic;
        my $code  = shift @$rules;

        my $understand
           = $part->{mustUnderstand}         ? '1'
           : defined $part->{mustUnderstand} ? '0'    # explicit 0
           :                                   undef;

        my $actor = $part->{destination};
        if(ref $actor eq 'ARRAY')
        {   $actor = join ' ', map {$self->roleURI($_)} @$actor }
        elsif(defined $actor)
        {   $actor =~ s/\b(\S+)\b/$self->roleURI($1)/ge }

        my $envpref = $self->schemas->prefixFor(SOAP11ENV);
        my $wcode = $understand || $actor
         ? sub
           { my ($doc, $v) = @_;
             my $xml = $code->($doc, $v);
             $xml->setAttribute("$envpref:mustUnderstand" => '1')
                 if defined $understand;
             $xml->setAttribute("$envpref:actor" => $actor)
                 if $actor;
             $xml;
           }
         : $code;

        push @rules, $label => $wcode;
    }

    (\@rules, $hlabels);
}

sub _writer_faults($)
{   my ($self, $args) = @_;
    my $faults = $args->{faults} ||= {};

    my (@rules, @flabels);

    # Include all namespaces in Fault, because we have no idea which namespace
    # is used for the error code. It automatically defines everything
    # which may be used in the detail block.
    my $wrfault = $self->_writer('SOAP-ENV:Fault'
      , include_namespaces => sub {$_[0] ne SOAP11ENV});

    while(my ($name, $fault) = each %$faults)
    {   my $part    = $fault->{part};
        my ($label, $type) = ($part->{name}, $part->{element});
        my $details = $self->_writer($type, elements_qualified => 'TOP'
         , include_namespaces => sub {$_[0] ne SOAP11ENV && $_[2]});

        my $code = sub
          { my ($doc, $data)  = (shift, shift);
            my %copy = %$data;
            $copy{faultactor} = $self->roleURI($copy{faultactor});
            my $det = delete $copy{detail};
            my @det = !defined $det ? () : ref $det eq 'ARRAY' ? @$det : $det;
            $copy{detail}{$type} = [ map {$details->($doc, $_)} @det ];
            $wrfault->($doc, \%copy);
          };

        push @rules, $name => $code;
        push @flabels, $name;
    }

    (\@rules, \@flabels);
}

##########
# Receiver

sub _reader_fault_reader()
{   my $self = shift;
    [ Fault => pack_type(SOAP11ENV, 'Fault')
    , $self->schemas->reader('SOAP-ENV:Fault'
        , hooks => { type => 'SOAP-ENV:detail', after => 'ELEMENT_ORDER'})
    ];
}

sub _reader_faults($$)
{   my ($self, $args, $faults) = @_;

    my %names;
    while(my ($name, $def) = each %$faults)
    {   $names{$def->{part}{element}} = $name;
    }

    sub
    {   my $data   = shift;
        my $faults  = $data->{Fault}    or return;

        my ($code_ns, $code_err) = unpack_type $faults->{faultcode};
        my ($err, @sub_err) = split /\./, $code_err;
        $err = 'Receiver' if $err eq 'Server';
        $err = 'Sender'   if $err eq 'Client';

        my %nice =
          ( code   => $faults->{faultcode}
          , class  => [ $code_ns, $err, @sub_err ]
          , reason => $faults->{faultstring}
          );

        $nice{role} = $self->roleAbbreviation($faults->{faultactor})
            if $faults->{faultactor};

        my $details = $faults->{detail};
        my $dettype = $details ? delete $details->{_ELEMENT_ORDER} : undef;

        my $name;
        if(!$details) { $name = 'error' }
        elsif(@$dettype && $names{$dettype->[0]})
        {   # fault named in WSDL
            $name = $names{$dettype->[0]};
            if(keys %$details==1)
            {   my (undef, $v) = %$details;
                if(ref $v eq 'HASH') { @nice{keys %$v} = values %$v }
                else { $nice{details} = $v }
            }
        }
        elsif(keys %$details==1)
        {   # simple generic fault, not in WSDL. Maybe internal server error
            ($name) = keys %$details;
            my $v = $details->{$name};
            my @v = ref $v eq 'ARRAY' ? @$v : $v;
            my @r = map { UNIVERSAL::isa($_, 'XML::LibXML::Node')
                          ? $_->textContent : $_} @v;
            $nice{$name} = @r==1 ? $r[0] : \@r;
        }
        else
        {   # unknown complex generic error
            $name = 'generic';
        }

        $data->{$name}   = \%nice;
        $faults->{_NAME} = $name;
        $data;
    };
}

sub replyMustUnderstandFault($)
{   my ($self, $type) = @_;

   +{ Fault =>
      { faultcode   => pack_type(SOAP11ENV, 'MustUnderstand')
      , faultstring => "SOAP mustUnderstand $type"
      }
    };
}

sub roleURI($) { $_[1] && $_[1] eq 'NEXT' ? SOAP11NEXT : $_[1] }

sub roleAbbreviation($) { $_[1] && $_[1] eq SOAP11NEXT ? 'NEXT' : $_[1] }

#-------------------------------------

#loaded from ::SOAP11::Encoding

#-------------------------------------


1;
