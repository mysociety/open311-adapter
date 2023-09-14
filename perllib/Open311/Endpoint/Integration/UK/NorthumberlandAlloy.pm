=head1 NAME

Open311::Endpoint::Integration::UK::NorthumberlandAlloy - Northumberland-specific parts of its Alloy integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::NorthumberlandAlloy;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'northumberland_alloy';
    return $class->$orig(%args);
};

sub service_request_content {
    '/open311/service_request_extended'
}

=head2 process_attributes

In addition to the default new request processing, this function:
* Finds or creates a contact and adds them under the C<contact.attribute_id> attribute.
* Gets category and group codes from the provided data.
* Looks up the category via C<category_list_code> and C<category_title_attribute>, adding this item under the 'category' attribute specified in C<request_to_resource_attribute_manual_mapping>.
* Looks up the category via C<group_list_code> and C<group_title_attribute>, adding this item the 'group' attribute specified in C<request_to_resource_attribute_manual_mapping>.

=cut

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    my $contact_resource_id = $self->_find_or_create_contact($args);
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    my $category_code = $self->_find_category_code($args->{service_code_alloy});
    if (my $group = $args->{attributes}->{group}) {
        foreach (keys %{$self->service_whitelist}) {
            if (my $alias = $self->service_whitelist->{$_}->{alias}) {
                if ($alias eq $group) {
                    $group = $_;
                }
            }
        }
        my $group_code = $self->_find_group_code($group);
        push @$attributes, {
           attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{group},
           value => [ $group_code ],
        };
    }
    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $category_code ],
    };

    return $attributes;
}

=head2 update_additional_attributes

Adds an update for the status attribute given by C<update_status_attribute_id>, using the mapping C<update_status_mapping>.

=cut

sub update_additional_attributes {
    my ($self, $args) = @_;

    return [{
        attributeCode => $self->config->{update_status_attribute_id},
        value => [ $self->config->{update_status_mapping}->{lc ($args->{status})} ]
    }];
}

=head2 skip_fetch_defect

Adds additional '_should_publish_defect' check.

=cut

sub skip_fetch_defect {
    my ($self, $defect) = @_;
    return 1 if $self->SUPER::skip_fetch_defect($defect);
    return !$self->_should_publish_defect($defect);
}

=head2 _should_publish_defect

Returns true iff C<defect_publish_flag> is set and true.

=cut

sub _should_publish_defect {
    my ($self, $defect) = @_;
    my $flag = $self->config->{ defect_publish_flag };
    my $attributes = $self->alloy->attributes_to_hash($defect);
    return $flag && $attributes->{ $flag };
}

1;
