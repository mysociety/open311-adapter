=head1 NAME

Integrations::Whitespace - Whitespace Work Software API integration

=head1 DESCRIPTION

This module provides an interface to the Whitespace Work Software Web Services API

=cut

package Integrations::Whitespace;

use strict;
use warnings;
use Moo;
use Tie::IxHash;
use SOAP::Lite; # +trace => [qw(debug)];
use JSON::MaybeXS;

with 'Role::Config';
with 'Role::Logger';

has attr => ( is => 'ro', default => 'http://webservices.whitespacews.com/' );
has username => ( is => 'lazy', default => sub { $_[0]->config->{username} } );
has password => ( is => 'lazy', default => sub { $_[0]->config->{password} } );
has url => ( is => 'lazy', default => sub { $_[0]->config->{url} } );

has endpoint => (
    is => 'lazy',
    default => sub {
        my $self = shift;

        $ENV{PERL_LWP_SSL_CA_PATH} = '/etc/ssl/certs' unless $ENV{DEV_USE_SYSTEM_CA_PATH};

        my $soap = SOAP::Lite->new(
            soapversion => 1.1,
            proxy => $self->url,
            default_ns => $self->attr,
            on_action => sub { $self->attr . $_[1] }
        );
        $soap->serializer->register_ns("http://schemas.datacontract.org/2004/07/WSAPIAuth.Web.Inputs", 'wsap');

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

sub call {
    my ($self, $method, @params) = @_;

    require SOAP::Lite;
    @params = make_soap_structure(@params);
    my $som = $self->endpoint->call(
        $method => @params,
        $self->security
    );

    # TODO: Better error handling
    die $som->faultstring if ($som->fault);

    return $som->result;
}

sub GetWorksheetDetails {
    my ($self, $params) = @_;

    return $self->call('GetWorksheetDetails', $params);
}

sub CreateWorksheet {
    my ($self, $params) = @_;

    if (!$params->{service_item_name}) {
        $self->logger->error("No service_item_name provided");
        die "No service_item_name provided";
    }

    my $service_mapping = $self->config->{service_mapping};
    my $service_params = $service_mapping->{$params->{service_item_name}};

    if (!$service_params) {
        $self->logger->error("No service mapping found for $params->{service_item_name}");
        die "No service mapping found for $params->{service_item_name}";
    }

    my $service_id = $params->{service_code} eq 'request_new_container'
        ? $service_params->{delivery_service_id}
        : $params->{service_code} eq 'request_container_removal'
        ? $service_params->{collection_service_id}
        : $service_params->{service_id};

    my $worksheet = ixhash(
        Uprn => $params->{uprn},
        ServiceId => $service_id,
        WorksheetReference => $params->{worksheet_reference},
        WorksheetMessage => $params->{worksheet_message},
        ServiceItemInputs => ixhash(
            'wsap:Input.CreateWorksheetInput.ServiceItemInput' => [
                ixhash(
                    'wsap:ServiceItemId' => $service_params->{service_item_id},
                    'wsap:ServiceItemName' => '',
                    'wsap:ServiceItemQuantity' => $params->{quantity},
                )
            ]
        ),
        ServicePropertyInputs => [
            {
                'wsap:Input.CreateWorksheetInput.ServicePropertyInput' => ixhash(
                    'wsap:ServicePropertyId' => 79,
                    'wsap:ServicePropertyValue' => $params->{assisted_yn},
                ),
            },
            {
                'wsap:Input.CreateWorksheetInput.ServicePropertyInput' => ixhash(
                    'wsap:ServicePropertyId' => 80,
                    'wsap:ServicePropertyValue' => $params->{location_of_containers},
                ),
            },
        ],
    );

    my $res = $self->call('CreateWorksheet', worksheetInput => $worksheet);
    $self->logger->debug("CreateWorksheet response: " . encode_json($res));

    if ($res->{ErrorCode}) {
        $self->logger->error("Error creating worksheet in Whitespace: $res->{ErrorDescription}");
        die "Error creating worksheet in Whitespace: $res->{ErrorDescription}";
    }

    my $worksheet_id = $res->{WorksheetResponse}->{anyType}->[0];
    $self->logger->info("Created worksheet in Whitespace: $worksheet_id");

    return $worksheet_id;
}

sub GetServices {
    my ($self, $service_id) = @_;

    my $res = $self->call('GetServices', serviceInput => ixhash( ServiceId => $service_id, IncludeCommercial => 0 ));

    return force_arrayref($res->{Services}, 'Service');
}

sub GetServiceItems {
    my ($self, $service_id) = @_;

    my $res = $self->call('GetServiceItems', serviceItemInput => ixhash( ServiceId => $service_id ));

    return force_arrayref($res->{ServiceItems}, 'ServiceItem');
}

sub force_arrayref {
    my ($res, $key) = @_;
    return [] unless $res;
    my $data = $res->{$key};
    return [] unless $data;
    $data = [ $data ] unless ref $data eq 'ARRAY';
    return $data;
}

sub make_soap_structure {
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = $_[$i] =~ /:/ ? $_[$i] : $_[$i];
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

sub ixhash {
    tie (my %data, 'Tie::IxHash', @_);
    return \%data;
}

1;
