package Open311::Endpoint::Service::UKCouncil::Bartec;
use Moo;
extends 'Open311::Endpoint::Service::UKCouncil';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => "report_url",
            description => "Report URL",
            datatype => "string",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "title",
            description => "Title",
            datatype => "string",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "description",
            description => "Description",
            datatype => "text",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "asset_details",
            description => "Asset information",
            datatype => "text",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "site_code",
            description => "Site code",
            datatype => "text",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "central_asset_id",
            description => "Central Asset ID",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "closest_address",
            description => "Closest address",
            datatype => "string",
            required => 0,
            automated => "server_set",
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "postcode",
            description => "postcode",
            datatype => "string",
            required => 0,
            automated => "server_set",
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "street",
            description => "Closest street",
            datatype => "string",
            required => 0,
            automated => "server_set",
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "house_no",
            description => "Closest house number",
            datatype => "string",
            required => 0,
            automated => "server_set",
        ),
    );

    return \@attributes;
}

1;
