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

    my $group = $args->{attributes}{group};
    my $service_code = $args->{service_code_alloy};

    my $category_code
        = $group
        ? $self->config->{service_whitelist}{$group}{$service_code}
        : $self->config->{service_whitelist}{''}{$service_code};

    # Appends to attribute[description] before attributes processed below.
    # May return question attributes to be added to $attributes list.
    my @question_attributes = $self->_munge_question_args(
        $args,
        $category_code,
    );

    my $attributes = $self->SUPER::process_attributes($args);
    push @$attributes, @question_attributes if @question_attributes;

    $self->_populate_category_and_group_attr(
        $attributes,
        $category_code,
    );

    return $attributes;
}

sub _munge_question_args {
    my ( $self, $args, $category_code ) = @_;

    my @q_attributes;

    if ( ref($category_code) eq 'HASH' ) {
        my $questions = $category_code->{questions};

        for my $q ( @$questions ) {
            my $code = $q->{code};
            my $q_text = $q->{description};
            my $answer = $args->{attributes}{$code};

            if ($answer) {
                $args->{attributes}{description} .= "\n\n$q_text\n$answer";

                if ( my $attr_code = $q->{alloy_attribute} ) {
                    my $answer_code
                        = $self->config->{question_mapping}{$attr_code}{$answer};

                    push @q_attributes, {
                        attributeCode => $attr_code,
                        value         => [$answer_code],
                    };
                }
            }
        }
    }

    return @q_attributes;
}

sub _populate_category_and_group_attr {
    my ( $self, $attr, $category_code ) = @_;

    if ( ref($category_code) eq 'HASH' ) {
        $category_code = $category_code->{alloy_code};
    }

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
        = $self->config->{category_id_to_service_area_id}{$group_code}
        || $self->config->{category_id_to_service_area_id}{$category_code};
    push @$attr, {
        attributeCode => $mapping->{service_area},
        value => [$srv_area_code],
    } if $srv_area_code;
}

1;
