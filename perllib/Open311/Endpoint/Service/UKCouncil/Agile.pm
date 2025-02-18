package Open311::Endpoint::Service::UKCouncil::Agile;
use Moo;
extends 'Open311::Endpoint::Service';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => 'fixmystreet_id',
            variable => 0, # set by server
            datatype => 'string',
            required => 1,
            automated => 'server_set',
            description => 'external system ID',
        ),

        Open311::Endpoint::Service::Attribute->new(
            code => "uprn",
            description => "UPRN reference",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "property_id",
            description => "Property ID",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'total_containers',
            description => 'Total number of requested containers',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'current_containers',
            description => 'Number of current containers',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'new_containers',
            description => 'Number of new containers (total requested minus current)',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'payment_method',
            description => 'Payment method: credit card or direct debit',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'payment',
            description => 'Payment amount in pence',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),

        # For cancellations
        Open311::Endpoint::Service::Attribute->new(
            code => 'reason',
            description => 'Cancellation reason',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'due_date',
            description => 'Cancellation date',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'customer_external_ref',
            description => 'Customer external ref',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),

        # For direct debit payments
        Open311::Endpoint::Service::Attribute->new(
            code => 'direct_debit_reference',
            description => 'Direct debit reference',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'direct_debit_start_date',
            description => 'Direct debit initial payment date',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),

        Open311::Endpoint::Service::Attribute->new(
            code => 'type',
            description => 'Denotes whether subscription request is a renewal or not',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),

    );

    return \@attributes;
}

1;
