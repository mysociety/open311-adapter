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
        my $soap = SOAP::Lite->new;
        $soap->proxy($self->url);
        $soap->on_action( sub { $self->action . $_[1]; } );
        $soap->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->fault->{Reason}{Text} : $soap->transport->status, "\n"; });
        $soap->serializer->register_ns("http://schemas.microsoft.com/2003/10/Serialization/Arrays", 'msArray'),
        # Prevent Base64 encoding
        my $lookup = $soap->serializer->typelookup;
        $lookup->{base64Binary}->[0] = 1000;
        $soap->serializer->typelookup($lookup);
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

    # SOAP::Lite uses some global constants to set e.g. the request's
    # Content-Type header and various envelope XML attributes. On new() it sets
    # up those XML attributes, and even if you call soapversion on the object's
    # serializer after, it does nothing if the global version matches the
    # object's current version (which it will!), and then uses those same
    # constants anyway. So we have to set the version globally before creating
    # the object (during the call to self->endpoint), and also during the
    # call() (because it uses the constants at that point to set the
    # Content-Type header), and then set it back after so it doesn't break
    # other users of SOAP::Lite.
    SOAP::Lite->soapversion(1.2);
    my $res = $self->endpoint->call(
        SOAP::Data->name($method)->attr({ xmlns => $self->namespace }),
        $self->security,
        $self->action_hdr($method),
        @params
    );
    SOAP::Lite->soapversion(1.1);
    $res = $res->result;
    return $res;
}

# Tie::IxHashes are used below because Echo complains if
# the XML fields are not received in the correct order.

sub GetEvent {
    my ($self, $guid, $type) = @_;
    $type ||= 'Guid';
    $self->call('GetEvent', ref => ixhash(
        Key => $type,
        Type => 'Event',
        Value => { 'msArray:anyType' => $guid },
    ));
}

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
            $_->{existing_id} ? (Guid => $_->{existing_id}) : (),
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

    my $source;
    if ($args->{uprn}) {
        my $uprn = ixhash(
            Key => 'Uprn',
            Type => 'PointAddress',
            Value => [
                # Must be a string, not a long
                { 'msArray:anyType' => SOAP::Data->value($args->{uprn})->type('string') },
            ],
        );
        $source = ixhash(
            EventObjectType => 'Source',
            ObjectRef => $uprn,
        );
    } else {
        my $points = $self->FindPoints($args->{lat}, $args->{long});
        my $object;
        if ($points->[0]) {
            $object = ixhash(
                Key => 'Id',
                Type => 'PointSegment',
                Value => [ { 'msArray:anyType' => $points->[0]->{Id} } ],
            );
        } elsif ($args->{usrn}) {
            $object = ixhash(
                Key => 'Usrn',
                Type => 'Street',
                Value => [
                    # Must be a string, not a long
                    { 'msArray:anyType' => SOAP::Data->value($args->{usrn})->type('string') },
                ],
            );
        }
        $source = ixhash(
            EventObjectType => 'Source',
            $object ? (ObjectRef => $object) : (),
            Location => ixhash(
                Latitude => $args->{lat},
                Longitude => $args->{long},
            ),
        );
    }
    my $data = ixhash(
        $args->{guid} ? (Guid => $args->{guid}) : (),
        $args->{data} ? (Data => extensible_data($args->{data})) : (),
        ClientReference => $args->{client_reference},
        EventObjects => { EventObject => $source },
        EventTypeId => $args->{event_type},
        ServiceId => $args->{service},
        $args->{reservation} ? (TaskReservations => [ map { { 'msArray:string' => $_ } } @{$args->{reservation}} ]) : (),
    );
    $self->call('PostEvent', event => $data);
}

sub UpdateEvent {
    my ($self, $args) = @_;

    my $data = ixhash(
        Id => $args->{id},
        Data => extensible_data($args->{data}),
    );
    $self->call('PostEvent', event => $data);
}

sub PerformEventAction {
    my ($self, $args) = @_;
    my $ref = ixhash(
        Key => $args->{id_type} || 'Guid',
        Type => 'Event',
        Value => [ { 'msArray:anyType' => $args->{service_request_id} }, ],
    );
    my @params;
    push @params, ActionTypeId => $args->{actiontype_id} || 3;
    if (!defined($args->{datatype_id}) || $args->{datatype_id}) {
        push @params, Data => { ExtensibleDatum => ixhash(
            DatatypeId => $args->{datatype_id} || 1,
            Value => $args->{description},
        ) };
    }
    push @params, EventRef => $ref;
    my $action = ixhash(@params);
    $self->call('PerformEventAction', action => $action);
}

sub FindPoints {
    my ($self, $lat, $lon) = @_;

    my $obj = ixhash(
        PointType => 'PointSegment',
        Near => ixhash(
            Latitude => $lat,
            Longitude => $lon,
        ),
    );
    my $res = $self->call('FindPoints', query => $obj);
    return force_arrayref($res, 'PointInfo');
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

sub force_arrayref {
    my ($res, $key) = @_;
    return [] unless $res;
    my $data = $res->{$key};
    return [] unless $data;
    $data = [ $data ] unless ref $data eq 'ARRAY';
    return $data;
}

1;
