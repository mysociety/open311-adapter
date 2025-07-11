package Open311::Endpoint::Service::UKCouncil::Whitespace;
use Moo;
extends 'Open311::Endpoint::Service';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => "uprn",
            description => "UPRN reference",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'fixmystreet_id',
            variable => 0, # set by server
            datatype => 'string',
            required => 1,
            automated => 'server_set',
            description => 'external system ID',
        ),
    );

    if ($self->service_name eq 'Bulky collection') {
        push @attributes,
            map {
                Open311::Endpoint::Service::Attribute->new(
                    code => $_,
                    description => $_,
                    datatype => "string",
                    required => 0,
                    automated => 'hidden_field',
                ),
            } qw(payment payment_method collection_date round_instance_id
            bulky_items pension disability bulky_location bulky_parking);
    } else {
        push @attributes,
        Open311::Endpoint::Service::Attribute->new(
            code => "service_item_name",
            description => "Service item name",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'assisted_yn',
            description => 'Assisted collection (Yes/No)',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'location_of_containers',
            description => 'Location of containers',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'location_of_letterbox',
            description => 'Location of letterbox',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'quantity',
            description => 'Number of containers',
            datatype => 'string',
            required => 0,
            automated => 'hidden_field',
        );
    }

    return \@attributes;
}

1;
