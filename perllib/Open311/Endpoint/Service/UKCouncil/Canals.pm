package Open311::Endpoint::Service::UKCouncil::Canals;

use Moo;
extends 'Open311::Endpoint::Service::UKCouncil';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
         @{ $self->SUPER::_build_attributes() },

         Open311::Endpoint::Service::Attribute->new(
            code => "location_description",
            description => "Location",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
         Open311::Endpoint::Service::Attribute->new(
            code => "region_c",
            description => "Region",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
    );

    return \@attributes;
}

1;
