=head1 NAME

Open311::Endpoint::Integration::Sugar - An integration with the Sugar CRM system

=head1 SYNOPSIS

This integration lets us populate categories

=cut

package Open311::Endpoint::Integration::Sugar;

use Moo;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::ConfigFile';

=head2 jurisdiction_id

Has the jurisdiction_id for matching reports to sugar

=cut

has jurisdiction_id => (
    is => 'ro',
);


=head2 service_list

This is a mapping of Sugar services to use for categories populating FMS.

=cut

has service_list => (
    is => 'ro',
);

=head2 service_extra_data

This is a mapping of Sugar attributes. Most categories
will have an  asset_id and some have extra questions

=cut

has service_extra_data => (
    is => 'ro',
);


=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil',
);

sub services {
    my $self = shift;

    my @services = ();
    for my $group (sort keys %{ $self->service_list }) {
        my $categories = $self->service_list->{$group};
        my $service_code;
        (my $format_group = $group) =~ s/\s+/-/g;
        for my $category (sort keys %{ $categories }) {
            ($service_code = $category) =~ s/\s+/_/g;
            my %service = (
                service_name => $category . ' (CRT: ' . $group . ')',
                description => $category,
                service_code => $format_group . '_' . $service_code,
                group => $group,
            );
            my $o311_service = $self->service_class->new(%service);
            my $extra = $self->service_list->{$group}{$category}{service_extra_data};
            foreach (@$extra) {
                $_->{datatype} = 'singlevaluelist';
                push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(%$_);
            }

            push @services, $o311_service;
        }
    }
    return @services;
}

1;
