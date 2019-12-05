package Open311::Endpoint::Service::UKCouncil::Ezytreev;
use Moo;

# Inherits from Confirm to workaround errors about extra attributes
# when creating a report.
extends 'Open311::Endpoint::Service::UKCouncil::Confirm';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => "tree_code",
            description => "Tree code",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
    );

    return \@attributes;
}

1;
