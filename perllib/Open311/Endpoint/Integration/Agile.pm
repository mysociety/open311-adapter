
=head1 NAME

Open311::Endpoint::Integration::Agile - An integration with the Agile backend

=head1 SYNOPSIS

This integration lets us fetch & post Green Garden Waste data to and from
Agile

=cut

package Open311::Endpoint::Integration::Agile;

use v5.14;

use Moo;
use Integrations::Agile;
use Open311::Endpoint::Service::UKCouncil::Agile;
use JSON::MaybeXS;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::EndpointConfig';
with 'Role::Logger';

has jurisdiction_id => ( is => 'ro' );

has category_mapping => (
    is      => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
);

has service_class => (
    is      => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Agile',
);

has integration_class => ( is => 'ro', default => 'Integrations::Agile' );

has agile => (
    is      => 'lazy',
    default => sub {
        $_[0]->integration_class->new(
            config_filename => $_[0]->jurisdiction_id );
    },
);

use constant PAYMENT_METHOD_MAPPING => {
    credit_card  => 'CREDITCARD',
    direct_debit => 'DIRECTDEBIT',
    csc => 'CREDITCARD',
};

sub get_integration {
    $_[0]->log_identifier( $_[0]->jurisdiction_id );
    return $_[0]->agile;
}

sub services {
    my ($self) = @_;

    my $services = $self->category_mapping;

    my @services = map {
        my $service = $services->{$_};
        my $name    = $service->{name};

        $self->service_class->new(
            service_name => $name,
            service_code => $_,
            description  => $name,
            keywords     => ['waste_only'],
            $service->{group}  ? ( group  => $service->{group} )  : (),
            $service->{groups} ? ( groups => $service->{groups} ) : (),
        );
    } keys %$services;

    return @services;
}

sub post_service_request {
    my ( $self, $service, $args ) = @_;

    $self->logger->info(
        "post_service_request(" . $service->service_code . ")" );
    $self->logger->debug(
        "post_service_request arguments: " . encode_json($args) );

    my $integration = $self->get_integration;

    my $is_free = $integration->IsAddressFree( $args->{attributes}{uprn} );

    if ( $is_free->{IsFree} eq 'True' ) {
        my $res = $integration->SignUp( {
            Firstname                 => $args->{first_name},
            Surname                   => $args->{last_name},
            Email                     => $args->{email},
            TelNumber                 => $args->{phone} || '',
            TitleCode                 => 'Default',
            CustomerExternalReference => '',
            ServiceContractUPRN       => $args->{attributes}{uprn},
            WasteContainerQuantity    => int( $args->{attributes}{new_containers} ) || 1,
            AlreadyHasBinQuantity => int( $args->{attributes}{current_containers} ) || 0,
            PaymentReference      => $args->{attributes}{PaymentCode},
            PaymentMethodCode     =>
                PAYMENT_METHOD_MAPPING->{ $args->{attributes}{payment_method} },

            # Used for FMS report ID
            ActionReference => $args->{attributes}{fixmystreet_id},

            # TODO
            DirectDebitDate => '',
            DirectDebitReference => '',
        } );

        # Expected response:
        # {
        #   CustomerExternalReference: string,
        #   CustomerReference: string,
        #   ServiceContractReference: string
        # }
        my $request = $self->new_request(
            service_request_id => $res->{ServiceContractReference},
        );

        return $request;

    } else {
        die 'UPRN '
            . $args->{attributes}{uprn}
            . ' already has a subscription or is invalid';
    }
}

1;
