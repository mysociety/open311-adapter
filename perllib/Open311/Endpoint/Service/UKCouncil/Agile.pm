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
            code => 'current_containers',
            description => 'Number of current containers',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'new_containers',
            description => 'Number of new containers',
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
    );

    return \@attributes;
}

1;
