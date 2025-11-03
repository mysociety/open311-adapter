
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

use constant SERVICE_TO_SUB_MAPPING => {
    garden_subscription        => \&_garden_subscription,
    garden_subscription_renew  => \&_garden_subscription_renew,
    garden_subscription_cancel => \&_garden_subscription_cancel,
    garden_subscription_amend  => \&_garden_subscription_amend,
};

use constant PAYMENT_METHOD_MAPPING => {
    credit_card  => 'CREDITDCARD',
    direct_debit => 'DIRECTDEBIT',
    csc => 'CREDITDCARD',
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

    # Garden Subscription may be a 'renew' type
    my $lookup = $service->service_code;
    $lookup .= "_$args->{attributes}{type}" if $args->{attributes}{type};

    my $sub = SERVICE_TO_SUB_MAPPING->{$lookup};

    die 'Service \'' . $service->service_code . '\' not handled' unless $sub;

    return &$sub( $self, $args );
}

sub _garden_subscription {
    my ( $self, $args ) = @_;

    my $integration = $self->get_integration;

    my $is_free
        = $args->{attributes}{renew_as_new_subscription}
        ? { IsFree => 'True' }
        : $integration->IsAddressFree( $args->{attributes}{uprn} );

    if ( $is_free->{IsFree} eq 'True' ) {
        my $res = $integration->SignUp( {
            Firstname                 => $args->{first_name},
            Surname                   => $args->{last_name},
            Email                     => $args->{email},
            TelNumber                 => $args->{phone} || '',
            TitleCode                 => 'Default',
            CustomerExternalReference => $args->{attributes}{customer_external_ref} || '',
            ServiceContractUPRN       => $args->{attributes}{uprn},
            WasteContainerQuantity    => int( $args->{attributes}{total_containers} ) || 1,
            AlreadyHasBinQuantity => int( $args->{attributes}{current_containers} ) || 0,
            PaymentReference      => $args->{attributes}{PaymentCode},
            PaymentMethodCode     =>
                PAYMENT_METHOD_MAPPING->{ $args->{attributes}{payment_method} },

            # Used for FMS report ID
            ActionReference => $args->{attributes}{fixmystreet_id},

            DirectDebitDate => $args->{attributes}{direct_debit_start_date} // '',
            DirectDebitReference => $args->{attributes}{direct_debit_reference} // '',
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

sub _garden_subscription_renew {
    my ( $self, $args ) = @_;

    my $integration = $self->get_integration;

    my $is_free = $integration->IsAddressFree( $args->{attributes}{uprn} );

    if ( $is_free->{IsFree} eq 'False' ) {
        my $res = $integration->Renew( {
            CustomerExternalReference => $args->{attributes}{customer_external_ref},
            ServiceContractUPRN       => $args->{attributes}{uprn},
            WasteContainerQuantity    => int( $args->{attributes}{total_containers} ) || 1,
            AlreadyHasBinQuantity     => int( $args->{attributes}{current_containers} ) || 0,
            PaymentReference          => $args->{attributes}{PaymentCode},
            PaymentMethodCode         =>
                PAYMENT_METHOD_MAPPING->{ $args->{attributes}{payment_method} },

            DirectDebitDate => $args->{attributes}{direct_debit_start_date} // '',
            DirectDebitReference => $args->{attributes}{direct_debit_reference} // '',
        } );

        # Expected response:
        # {
        #   Id: int,
        #   Address: string,
        #   ServiceContractStatus: string,
        #   WasteContainerType: string,
        #   WasteContainerQuantity: int,
        #   StartDate: string,
        #   EndDate: string,
        #   ReminderDate: string,
        # }
        my $request = $self->new_request(
            service_request_id => $res->{Id}, # TODO Is this correct?
        );

        return $request;

    } else {
        die 'UPRN '
            . $args->{attributes}{uprn}
            . ' does not have a subscription to be renewed, or is invalid';
    }
}

sub _garden_subscription_cancel {
    my ( $self, $args ) = @_;

    my $integration = $self->get_integration;

    my $is_free = $integration->IsAddressFree( $args->{attributes}{uprn} );

    if ( $is_free->{IsFree} eq 'False' ) {
        my $res = $integration->Cancel( {
            CustomerExternalReference => $args->{attributes}{customer_external_ref},
            ServiceContractUPRN       => $args->{attributes}{uprn},
            Reason                    => $args->{attributes}{reason},
            DueDate                   => $args->{attributes}{due_date},
        } );

        # Expected response:
        # {
        #   Reference: string,
        #   Status: string,
        # }
        my $request = $self->new_request(
            service_request_id => $res->{Reference},
        );

        return $request;

    } else {
        die 'UPRN '
            . $args->{attributes}{uprn}
            . ' does not have a subscription to be cancelled, or is invalid';
    }
}

sub _garden_subscription_amend {
    my ( $self, $args) = @_;

    my $integration = $self->get_integration;

    my $is_free = $integration->IsAddressFree( $args->{attributes}{uprn} );

    if ( $is_free->{IsFree} ne 'False' ) {
            die 'UPRN '
                . $args->{attributes}{uprn}
                . ' does not have a subscription to be amended, or is invalid';
    }

    # We have to call a different Agile API method depending on whether
    # containers are being added or taken away.
    my $current_bins = int( $args->{attributes}{current_containers} );
    my $adjust_bins = int( $args->{attributes}{new_containers} );
    if ( $adjust_bins > 0 ) {
        my $res = $integration->AddBin( {
            CustomerExternalReference => $args->{attributes}{customer_external_ref},
            ServiceContractUPRN       => $args->{attributes}{uprn},
            AlreadyHasBinQuantity     => $current_bins,
            QuantityToAdd             => $adjust_bins,
        } );

        # Expected response:
        # {
        #   Reference: string,
        #   Status: string,
        # }
        my $request = $self->new_request(
            service_request_id => $res->{Reference},
        );

        return $request;
    } elsif ( $adjust_bins < 0 ) {
        my $res = $integration->RemoveBin( {
            CustomerExternalReference => $args->{attributes}{customer_external_ref},
            ServiceContractUPRN       => $args->{attributes}{uprn},
            QuantityToRemove          => abs($adjust_bins),
        } );

        # Expected response:
        # {
        #   Reference: string,
        #   Status: string,
        # }
        my $request = $self->new_request(
            service_request_id => $res->{Reference},
        );

        return $request;
    } else {
        die 'Amendment for UPRN '
            . $args->{attributes}{uprn}
            . " does not seem to change number of bins?! Current: $current_bins Adjust: $adjust_bins";
    }
}
1;
