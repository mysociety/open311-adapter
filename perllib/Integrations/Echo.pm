package Integrations::Echo;

use strict;
use warnings;
use Moo;
use SOAP::Lite;
use Tie::IxHash;

with 'Role::Config';

has namespace => ( is => 'ro', default => 'http://www.twistedfish.com/xmlns/echo/api/v1' );
has action => ( is => 'lazy', default => sub { $_[0]->namespace . "/Service/" } );
has username => ( is => 'lazy', default => sub { $_[0]->config->{username} } );
has password => ( is => 'lazy', default => sub { $_[0]->config->{password} } );
has url => ( is => 'lazy', default => sub { $_[0]->config->{url} } );

has endpoint => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        $ENV{PERL_LWP_SSL_CA_PATH} = '/etc/ssl/certs';
        SOAP::Lite->soapversion(1.2);
        my $soap = SOAP::Lite->new;
        $soap->proxy($self->url);
        $soap->on_action( sub { $self->action . $_[1]; } );
        $soap->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->fault->{Reason}{Text} : $soap->transport->status, "\n"; });
        $soap->serializer->register_ns("http://schemas.microsoft.com/2003/10/Serialization/Arrays", 'msArray'),
        return $soap;
    },
);

has security => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        SOAP::Header->name("Security")->attr({
            'mustUnderstand' => 'true',
            'xmlns' => 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd'
        })->value(
            \SOAP::Header->name(
                "UsernameToken" => \SOAP::Header->value(
                    SOAP::Header->name('Username', $self->username),
                    SOAP::Header->name('Password', $self->password),
                )
            )
        );
    },
);

sub action_hdr {
    my ($self, $method) = @_;
    SOAP::Header->name("Action")->attr({
        'xmlns' => 'http://www.w3.org/2005/08/addressing',
    })->value(
        $self->action . $method
    );
}

sub call {
    my ($self, $method, @params) = @_;

    @params = make_soap_structure(@params);
    my $res = $self->endpoint->call(
        SOAP::Data->name($method)->attr({ xmlns => $self->namespace }),
        $self->security,
        $self->action_hdr($method),
        @params
    );
    $res = $res->result;
    return $res;
}

# Tie::IxHashes are used below because Echo complains if
# the XML fields are not recieved in the correct order.

sub GetEventType {
    my ($self, $id) = @_;
    my $obj = ixhash(
        Key => 'Id',
        Type => 'EventType',
        Value => [
            { 'msArray:anyType' => $id },
        ],
    );
    $self->call('GetEventType', ref => $obj);
}

sub extensible_data {
    my $data = shift;
    my @data;
    foreach (@$data) {
        my $data = ixhash(
            $_->{childdata} ? (ChildData => extensible_data($_->{childdata})) : (),
            DatatypeId => $_->{id},
            Value => $_->{value},
        );
        push @data, { ExtensibleDatum => $data };
    }
    return \@data;
}

sub PostEvent {
    my ($self, $args) = @_;

    my $uprn = ixhash(
        Key => 'Uprn',
        Type => 'PointAddress',
        Value => [
            # Must be a string, not a long
            { 'msArray:anyType' => SOAP::Data->value($args->{uprn})->type('string') },
        ],
    );
    my $source = ixhash(
        EventObjectType => 'Source',
        ObjectRef => $uprn,
    );
    my $data = ixhash(
        $args->{data} ? (Data => extensible_data($args->{data})) : (),
        EventObjects => { EventObject => $source },
        EventTypeId => $args->{event_type},
        ServiceId => $args->{service},
    );
    $self->call('PostEvent', event => $data);
}

sub PerformEventAction {
    my ($self, $args) = @_;
    my $ref = ixhash(
        Key => 'Id',
        Type => 'Event',
        Value => [ { 'msArray:anyType' => $args->{service_request_id} }, ],
    );
    my $action = ixhash(
        ActionTypeId => 3,
        Data => { ExtensibleDatum => ixhash(
            DatatypeId => 1,
            Value => $args->{description},
        ) },
        EventRef => $ref,
    );
    $self->call('PerformEventAction', action => $action);

}

sub ixhash {
    tie (my %data, 'Tie::IxHash', @_);
    return \%data;
}

sub make_soap_structure {
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = $_[$i];
        my $v = $_[$i+1];
        my $val = $v;
        my $d = SOAP::Data->name($name);
        if (ref $v eq 'HASH') {
            $val = \SOAP::Data->value(make_soap_structure(%$v));
        } elsif (ref $v eq 'ARRAY') {
            my @map = map { make_soap_structure(%$_) } @$v;
            $val = \SOAP::Data->value(SOAP::Data->name('dummy' => @map));
        }
        push @out, $d->value($val);
    }
    return @out;
}

1;
