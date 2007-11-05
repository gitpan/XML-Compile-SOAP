#!/usr/bin/perl
# Test SOAP encoding

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Test::Deep qw/cmp_deeply/;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::SOAP11::Client;
use XML::Compile::SOAP::Util qw/:soap11/;
use XML::Compile::Util       qw/SCHEMA2001 pack_type/;

use Test::More tests => 77;
use XML::LibXML;
use TestTools qw/compare_xml/;

my $TestNS = 'http://test-ns';

my $soap = XML::Compile::SOAP11::Client->new;
ok(defined $soap, 'created client');
isa_ok($soap, 'XML::Compile::SOAP11::Client');

my $soapenc = SOAP11ENC;
my $xsi     = SCHEMA2001.'-instance';
my $int     = pack_type SCHEMA2001, 'int';
my $string  = pack_type SCHEMA2001, 'string';

$soap->startDecoding;

sub check_decode($$$$)
{   my ($item, $expect_data, $expect_index, $text) = @_;

    my $data = <<__XML;
<SOAP-ENC:Body
  xmlns:SOAP-ENC="$soapenc"
  xmlns:xsi="$xsi"
  xmlns:xsd="$SchemaNS"
  xmlns:test="$TestNS"
  >

  $item

</SOAP-ENC:Body>
__XML

    ok(1, "next test: $text");
    my $doc = XML::LibXML->new->parse_string($data);
    isa_ok($doc, 'XML::LibXML::Document');

    my $body = $doc->documentElement;
    isa_ok($body, 'XML::LibXML::Element');

    my @elements = grep { $_->isa('XML::LibXML::Element') } $body->childNodes;
    my ($h, $i) = $soap->dec(@elements);

    cmp_deeply($h, $expect_data);
    cmp_deeply($i, $expect_index);
}

check_decode '<SOAP-ENC:int>41</SOAP-ENC:int>'
  , [ { _ => 41, _TYPE => "{$soapenc}int" } ]
  , {}
  , 'soapenc simple';

my $out1 = { id => 'hhtg', _ => 42, _TYPE => "{$soapenc}int" };
check_decode '<SOAP-ENC:int id="hhtg">42</SOAP-ENC:int>'
  , [ $out1 ]
  , { hhtg => $out1 }
  , 'soapenc simple with id';

check_decode '<code xsi:type="xsd:int">43</code>'
  , [ { _ => 43, _TYPE => "{$SchemaNS}int" } ]
  , {}
  , 'typed';

check_decode <<__XML, [ $out1, $out1 ], { hhtg => $out1 }, 'ref';
<SOAP-ENC:int id="hhtg">42</SOAP-ENC:int>
<ref href="#hhtg"/>
__XML

$soap->schemas->importDefinitions( <<__SCHEMA );
<schema targetNamespace="$TestNS"
     xmlns="$SchemaNS"
     xmlns:SOAP-ENC="$soapenc">
   <element name="myFavoriteNumbers" type="SOAP-ENC:Array" />
</schema>
__SCHEMA

my $a1 =
  { _NAME => pack_type($TestNS, 'myFavoriteNumbers'), id => 'array1'
  , _ => [ { _TYPE => $int, _ => 3 }, { _TYPE => $int, _ => 4 } ]
  };

check_decode <<__XML, [ $a1, $a1 ], {array1 => $a1}, 'array 1';
<test:myFavoriteNumbers id="array1" SOAP-ENC:arrayType="xsd:int[2]">
  <number>3</number>
  <number>4</number>
</test:myFavoriteNumbers>
<ref href="#array1"/>
__XML

my $encstring = pack_type SOAP11ENC, 'string';
my $encarray  = pack_type SOAP11ENC, 'Array';
my $a2 =
  { _NAME => $encarray, id => 'array2'
  , _ => [ { _TYPE => $encstring, _ => 3 }, { _TYPE => $encstring, _ => 4 } ]
  };

check_decode <<__XML, [$a2, $a2], {array2 => $a2}, 'array 2';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:int[2]" id="array2">
  <SOAP-ENC:string>3</SOAP-ENC:string>
  <SOAP-ENC:string>4</SOAP-ENC:string>
</SOAP-ENC:Array>
<ref href="#array2"/>
__XML

my $e3t = 'Of Mans First ... ... and all our woe,';
my $e3u = 'http://www.dartmouth.edu/~milton/reading_room/';
my $a3 =
  { _NAME => $encarray
  , _ => [ { _TYPE => $int, _ => 12345}
         , { _TYPE => pack_type(SCHEMA2001, 'decimal'),
                _ => Math::BigFloat->new(6.789) }
         , { _TYPE => $string, _ => $e3t }
         , { _TYPE => pack_type(SCHEMA2001, 'anyURI'), _ => $e3u }
         ]
  };

check_decode <<__XML, [$a3], {}, 'array 3';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:anyType[4]">
   <thing xsi:type="xsd:int">12345</thing>
   <thing xsi:type="xsd:decimal">6.789</thing>
   <thing xsi:type="xsd:string">$e3t</thing>
   <thing xsi:type="xsd:anyURI">$e3u</thing>
</SOAP-ENC:Array>
__XML

$soap->schemas->importDefinitions( <<__SCHEMA );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:me="$TestNS">

  <element name="Order">
    <complexType>
      <sequence>
        <element name="Product" type="string"/>
        <element name="Price"   type="decimal"/>
      </sequence>
    </complexType>
  </element>

</schema>
__SCHEMA

my $ot = pack_type $TestNS, 'Order';
my $a4 =
  { _NAME => $encarray
  , _ => [ { _TYPE => $ot, Product => 'Apple'
           , Price => Math::BigFloat->new(1.56) }
         , { _TYPE => $ot, Product => 'Peach'
           , Price => Math::BigFloat->new(1.48) }
         ]
  };

check_decode <<__XML, [$a4], {}, 'order';
<SOAP-ENC:Array SOAP-ENC:arrayType="test:Order[2]">
  <Order>
    <Product>Apple</Product>
    <Price>1.56</Price>
  </Order>
  <Order>
    <Product>Peach</Product>
    <Price>1.48</Price>
  </Order>
</SOAP-ENC:Array>
__XML

my $a5_1 =
 { _NAME => $encarray
 , id => 'array-1'
 , _ => [ { _TYPE => $string, _ => 'r1c1' }
        , { _TYPE => $string, _ => 'r1c2' }
        , { _TYPE => $string, _ => 'r1c3' }
        ]
 };

my $a5_2 =
 { _NAME => $encarray
 , id => 'array-2'
 , _ => [ { _TYPE => $string, _ => 'r2c1' }
        , { _TYPE => $string, _ => 'r2c2' }
        ]
 };

my $a5 =
 { _NAME => $encarray
 , id => 'array-3'
 , _ => [ $a5_1, $a5_2 ]
 };
  
my $i5 = {'array-1' => $a5_1, 'array-2' => $a5_2, 'array-3' => $a5};
check_decode <<__XML, [$a5, $a5_1, $a5_2], $i5, 'multidim';
<SOAP-ENC:Array id="array-3" SOAP-ENC:arrayType="xsd:string[][2]">
  <item href="#array-1"/>
  <item href="#array-2"/>
</SOAP-ENC:Array>
<SOAP-ENC:Array id="array-1" SOAP-ENC:arrayType="xsd:string[3]">
  <item>r1c1</item>
  <item>r1c2</item>
  <item>r1c3</item>
</SOAP-ENC:Array>
<SOAP-ENC:Array id="array-2" SOAP-ENC:arrayType="xsd:string[2]">
  <item>r2c1</item>
  <item>r2c2</item>
</SOAP-ENC:Array>
__XML

=pod Arrays by extension not yet supported

$soap->schemas->importDefinitions( <<__SCHEMA );
<schema targetNamespace="$TestNS"
        xmlns="$SchemaNS"
        xmlns:tns="$TestNS"
        xmlns:SOAP-ENC="$soapenc"
  >

<simpleType name="phoneNumber">
  <restriction base="string"/>
</simpleType>

<element name="ArrayOfPhoneNumbers">
  <complexType>
    <complexContent>
      <extension base="SOAP-ENC:Array">
        <sequence>
          <element name="phoneNumber" type="tns:phoneNumber"
            maxOccurs="unbounded"/>
        </sequence>
      </extension>
    </complexContent>
  </complexType>
</element>

</schema>
__SCHEMA

check_decode <<__XML, [], {}, 'inherited array';
<test:ArrayOfPhoneNumbers>
   <phoneNumber>206-555-1212</phoneNumber>
   <phoneNumber>1-888-123-4567</phoneNumber>
</test:ArrayOfPhoneNumbers>
__XML

}

=cut

my $a7 =
  { _NAME => $encarray
  , _ => [ undef, undef
         , { _TYPE => $string, _ => 'The third element' }
         , { _TYPE => $string, _ => 'The fourth element' }
         , undef ]
  };
  
check_decode <<__XML, [ $a7 ], {}, 'array with offset';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[5]" SOAP-ENC:offset="[2]">
  <item>The third element</item>
  <item>The fourth element</item>
</SOAP-ENC:Array>
__XML

my $a8 =
  { _NAME => $encarray
  , _ => [ undef
         , { _TYPE => $string, _ => 'The second element' }
         , undef
         , { _TYPE => $string, _ => 'The fourth element' }
         , undef ]
  };

check_decode <<__XML, [ $a8 ], {}, 'array with position';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[5]">
   <item SOAP-ENC:position="[3]">The fourth element</item>
   <item SOAP-ENC:position="[1]">The second element</item>
</SOAP-ENC:Array>
__XML

my @e9 = map { +{_TYPE => $string, _ => $_} }
   qw/r1c1 r1c2 r1c3 r2c1 r2c2 r2c3/;

my $a9 =
 { _NAME => $encarray
 , _ => [ [ $e9[0], $e9[1], $e9[2] ]
        , [ $e9[3], $e9[4], $e9[5] ] ]
 };

check_decode <<__XML, [ $a9 ], {}, 'multidim';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[2,3]">
  <item>r1c1</item>
  <item>r1c2</item>
  <item>r1c3</item>
  <item>r2c1</item>
  <item>r2c2</item>
  <item>r2c3</item>
</SOAP-ENC:Array>
__XML

my $a10 =
 { _NAME => $encarray
 , _ => [ [ $e9[0], undef, $e9[2] ]
        , [ $e9[3], $e9[4] ] ]
 };

check_decode <<__XML, [ $a10 ], {}, 'multidim with position';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[2,3]">
   <item SOAP-ENC:position="[0,0]">r1c1</item>
   <item SOAP-ENC:position="[0,2]">r1c3</item>
   <item SOAP-ENC:position="[1,0]">r2c1</item>
   <item SOAP-ENC:position="[1,1]">r2c2</item>
</SOAP-ENC:Array>
__XML

my $a11_2 = { _NAME => $encarray, id => 'array-1'};
$a11_2->{_}[2][2] = { _TYPE => $string, _ => 'Third row, third col' };
$a11_2->{_}[7][2] = { _TYPE => $string, _ => 'Eight row, third col' };
my $a11_1 = { _NAME => $encarray, _ => [undef, undef, $a11_2, undef] };

check_decode <<__XML, [$a11_1, $a11_2], {'array-1' => $a11_2},'multidim nested';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[,][4]" SOAP-ENC:offset="[2]">
  <SOAP-ENC:Array href="#array-1"/>
</SOAP-ENC:Array>
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[10,10]" id="array-1">
  <item SOAP-ENC:position="[2,2]">Third row, third col</item>
  <item SOAP-ENC:position="[7,2]">Eight row, third col</item>
</SOAP-ENC:Array>
__XML

check_decode <<__XML, [$a11_1], {'array-1' => $a11_2},'multidim nested';
<SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[,][4]" SOAP-ENC:offset="[2]">
  <SOAP-ENC:Array SOAP-ENC:arrayType="xsd:string[10,10]" id="array-1">
    <item SOAP-ENC:position="[2,2]">Third row, third col</item>
    <item SOAP-ENC:position="[7,2]">Eight row, third col</item>
  </SOAP-ENC:Array>
</SOAP-ENC:Array>
__XML
