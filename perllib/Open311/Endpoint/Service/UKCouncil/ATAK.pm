package Open311::Endpoint::Service::UKCouncil::ATAK;
use Moo;
extends 'Open311::Endpoint::Service::UKCouncil';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => "location_name",
            description => "Location Name",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
            allow_any_attributes => 1,
        ),

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
            code => "detail",
            description => "Detail",
            datatype => "text",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "group",
            description => "Group",
            datatype => "string",
            required => 1,
            automated => 'server_set',
        ),
    );

    return \@attributes;
}

1;
