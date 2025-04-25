package Open311::Endpoint::Integration::UK::Gloucester;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'gloucester_alloy';
    return $class->$orig(%args);
};

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    $self->_populate_category_and_group_attr(
        $attributes,
        $args->{service_code_alloy},
        $args->{attributes}{group},
    );

    return $attributes;
}

sub _populate_category_and_group_attr {
    my ( $self, $attr, $service_code, $group ) = @_;

    my $category_code
        = $group
        ? $self->config->{service_whitelist}{$group}{$service_code}
        : $self->config->{service_whitelist}{''}{$service_code};

    # NB FMS category == Alloy subcategory; FMS group == Alloy category

    my $mapping = $self->config->{category_attribute_mapping};

    push @$attr, {
        attributeCode => $mapping->{subcategory},
        value => [$category_code],
    };

    my $group_code
        = $self->config->{subcategory_id_to_category_id}{$category_code};
    push @$attr, {
        attributeCode => $mapping->{category},
        value => [$group_code],
    };

    my $srv_area_code
        = $self->config->{category_id_to_service_area_id}{$group_code};
    push @$attr, {
        attributeCode => $mapping->{service_area},
        value => [$srv_area_code],
    } if $srv_area_code;
}

1;
