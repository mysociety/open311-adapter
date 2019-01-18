package Open311::Endpoint::Integration::UK::Northamptonshire;

use Moo;
extends 'Open311::Endpoint::Integration::Alloy';

use List::Util 'first';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'northamptonshire_alloy';
    return $class->$orig(%args);
};

use Integrations::Alloy::Northamptonshire;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Alloy::Northamptonshire'
);

sub service_request_id_for_resource {
    my ($self, $resource) = @_;

    my $attribute_id = $self->config->{inspection_id_attribute};
    my $attribute = first { $_->{attributeId} eq $attribute_id } @{ $resource->{values} };

    # We can't default to e.g. resourceId because it'll make later
    # identification of this resource very complicated.
    die "Couldn't find inspection ID for resource" unless $attribute && $attribute->{value};

    return $attribute->{value};
}


1;
