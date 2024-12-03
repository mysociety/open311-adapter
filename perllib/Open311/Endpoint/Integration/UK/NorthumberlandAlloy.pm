=head1 NAME

Open311::Endpoint::Integration::UK::NorthumberlandAlloy - Northumberland-specific parts of its Alloy integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::NorthumberlandAlloy;

use List::Util qw(any);
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

sub services {
    my $self = shift;

    my @services = $self->SUPER::services;
    foreach (@services) {
        if (any { $_ eq 'Street Lighting' || $_ eq 'Winter (Snow/Ice)' } @{$_->groups}) {
            push @{$_->attributes}, Open311::Endpoint::Service::Attribute->new(
                code => 'feature_id',
                description => 'Feature ID',
                datatype => 'string',
                required => 0,
                automated => 'hidden_field',
            );
        }
    }
    return @services;
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

    $self->_populate_category_and_group_attr(
        $attributes,
        $args->{service_code_alloy},
        $args->{attributes}{group},
    );

    return $attributes;
}

sub _populate_category_and_group_attr {
    my ( $self, $attr, $service_code, $group ) = @_;

    my $category_code = $self->_find_category_code($service_code);
    if ($group) {
        foreach ( keys %{ $self->service_whitelist } ) {
            if ( my $alias = $self->service_whitelist->{$_}->{alias} ) {
                if ( $alias eq $group ) {
                    $group = $_;
                }
            }
        }
        my $group_code = $self->_find_group_code($group);
        push @$attr, {
            attributeCode =>
                $self->config->{request_to_resource_attribute_manual_mapping}
                {group},
            value => [$group_code],
        };
    }

    push @$attr, {
        attributeCode =>
            $self->config->{request_to_resource_attribute_manual_mapping}
            {category},
        value => [$category_code],
    };
}

=head2 update_additional_attributes

Adds an update for the status attribute given by C<update_status_attribute_id>, using the mapping C<update_status_mapping>.

Adds an update for 'extra_details' field ('FMS Extra Details' on Alloy end).

Adds an update for the assigned user ('Assigned to' on Alloy end).

Adds an update for category ('Request Category' on Alloy end), and group
if applicable.

=cut

sub update_additional_attributes {
    my ($self, $args) = @_;

    my $attr = [
        {   attributeCode => $self->config->{update_status_attribute_id},
            value         => [
                $self->config->{update_status_mapping}
                    ->{ lc( $args->{status} ) }
            ],
        },
        {   attributeCode =>
                $self->config->{inspection_attribute_mapping}{extra_details},
            value => $args->{attributes}{extra_details},
        },
    ];

    if ( exists $args->{attributes}{assigned_to_user_email} ) {
        my $email = $args->{attributes}{assigned_to_user_email};

        if ($email) {
            # TODO Handle failure

            # Search for existing user
            my $mapping = $self->config->{assigned_to_user_mapping};
            my $body = $self->find_item_body(
                dodi_code      => $mapping->{design},
                attribute_code => $mapping->{email_attribute},
                search_term    => $args->{attributes}{assigned_to_user_email},
            );

            my $res = $self->alloy->search($body);

            # We don't update if user does not exist in Alloy
            if (@$res) {
                push @$attr, {
                    attributeCode =>
                        $self->config->{inspection_attribute_mapping}
                        {assigned_to_user},
                    value => [ $res->[0]{itemId} ],
                };
            }
        } else {
            # Unset user
            push @$attr, {
                attributeCode =>
                    $self->config->{inspection_attribute_mapping}
                    {assigned_to_user},
                value => [],
            };
        }
    }

    if ( my $service_code = $self->_munge_service_code( $args->{service_code} || '' ) ) {
        $self->_populate_category_and_group_attr(
            $attr,
            $service_code,
            $args->{attributes}{group},
        );
    }

    return $attr;
}

=head2 get_assigned_to_users

Looks up FMS users on Alloy, given updates, and returns usernames
('firstname surname') and emails.

=cut

sub get_assigned_to_users {
    my ( $self, @updates ) = @_;

    return {} unless @updates;

    # Get unique customerRequestAssignedTo IDs
    my %user_ids;
    for my $u (@updates) {
        my $attr = $self->alloy->attributes_to_hash($u);
        map { $user_ids{$_} = 1 } @{
            $attr->{
                $self->config->{inspection_attribute_mapping}
                    {assigned_to_user}
            } // []
        };
    }

    return {} unless %user_ids;

    my $mapping = $self->config->{assigned_to_user_mapping};

    my $res = $self->alloy->search(
        {   properties => {
                dodiCode => $mapping->{design},
                collectionCode => 'Live',
                attributes     => [
                    $mapping->{username_attribute},
                    $mapping->{email_attribute},
                    # TODO Do we also want phone?
                ],
            },
            children => [
                {   type     => "Equals",
                    children => [
                        {   type       => 'ItemProperty',
                            properties => { itemPropertyName => 'itemID', },
                        },
                        {   type       => 'AlloyId',
                            properties => { value => [ keys %user_ids ] }
                        }
                    ],
                },
            ],
        },
    );

    return {} unless @$res;

    my %users;

    for (@$res) {
        my $attr = $self->alloy->attributes_to_hash($_);
        $users{ $_->{itemId} } = {
            assigned_user_name  => $attr->{ $mapping->{username_attribute} },
            assigned_user_email => $attr->{ $mapping->{email_attribute} },
        };
    }

    return \%users;
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
