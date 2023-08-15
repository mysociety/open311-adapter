package Open311::Endpoint::Service::UKCouncil::CentralBedfordshireFlytipping;
use Moo;
extends 'Open311::Endpoint::Service::UKCouncil';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

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
            code => "report_url",
            required => 1,
            datatype => "string",
            description => "Report URL",
            automated => 'server_set'
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "reported_by_staff",
            required => 1,
            datatype => "singlevaluelist",
            description => "Reported by staff",
            automated => 'server_set',
            "values" => {
                "Yes" => "Yes",
                "No" => "No",
            }
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "staff_reporter",
            required => 0,
            datatype => "text",
            description => "name of the staff reporter",
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "land_type",
            variable => 1,
            required => 1,
            datatype => "singlevaluelist",
            description => "The flytip is located on:",
            "values" => {
                "Roadside / verge" => "Roadside / verge",
                "Footpath" => "Footpath",
                "Private land" => "Private land",
                "Public land" => "Public land",
            }
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "type_of_waste",
            variable => 1,
            required => 1,
            datatype => "multivaluelist",
            description => "What type of waste is it?",
            "values" => {
                "Asbestos" => "Asbestos",
                "Black bags" => "Black bags",
                "Building materials" => "Building materials",
                "Chemical / oil drums" => "Chemical / oil drums",
                "Construction waste" => "Construction waste",
                "Electricals" => "Electricals",
                "Fly posting" => "Fly posting",
                "Furniture" => "Furniture",
                "Green / garden waste" => "Green / garden waste",
                "Household waste / black bin bags" => "Household waste / black bin bags",
                "Mattress or bed base" => "Mattress or bed base",
                "Trolleys" => "Trolleys",
                "Tyres" => "Tyres",
                "Vehicle parts" => "Vehicle parts",
                "White goods - fridge, freezer, washing machine etc" => "White goods - fridge, freezer, washing machine etc",
                "Other" => "Other",
            }
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "fly_tip_witnessed",
            variable => 1,
            required => 1,
            datatype => "singlevaluelist",
            description => "Did you observe this taking place?",
            "values" => {
                "Yes" => "Yes",
                "No" => "No",
            }
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "fly_tip_date_and_time",
            variable => 1,
            # Only required when fly tip witnessed, expecting client to enforce this.
            required => 0,
            datatype => "datetime",
            description => "When did this take place?"
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "description_of_alleged_offender",
            variable => 1,
            # Only required when fly tip witnessed, expecting client to enforce this.
            required => 0,
            datatype => "text",
            description => "Please provide any futher information which may help identify the alleged offender"
        ),
    );

    return \@attributes;
}

1;
