=head1 NAME

Open311::Endpoint::Integration::Sugar - An integration with the Sugar CRM system

=head1 SYNOPSIS

This integration lets us populate categories

=cut

package Open311::Endpoint::Integration::Sugar;

use Moo;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

use Integrations::Rest;

=head2 jurisdiction_id

Has the jurisdiction_id for matching reports to sugar

=cut

has jurisdiction_id => (
    is => 'ro',
);

=head2 integration_class

Set the core class for integrating with Sugar

=cut

has integration_class => (
    is => 'ro',
    default => 'Integrations::Rest'
);

=head2 sugar

Instantiate the configuration as sugar.

The REST integration requires a 'caller' for identifying logging messages

=cut

has rest => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(
        config_filename => $_[0]->jurisdiction_id,
        caller => 'Sugar',
    ) }
);

=head2 api_calls

Mapping of keys to api call strings

=cut

has api_calls => (
    is => 'ro',
);

=head2 username and password

Login username and password required to get an access token

=cut

has username => (
    is => 'ro',
);

has password => (
    is => 'ro',
);

has client_id => (
    is => 'ro',
);

=head2 access_token

API calls must pass an access_token which is fetched using the username and password.
It lasts an hour which should be enough for the lifetime of open311 requests so
no need to save the refresh token

=cut

has access_token => (
    is => 'rw',
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

=head2 get_integration

Set the integration as 'sugar' which is a Rest integration

=cut

sub get_integration {
    return $_[0]->rest;
};

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

=head2 do_login

Prior to calls requiring authorisation we need to log in and set the access_token

=cut

sub _do_login {
    my $self = shift;

    my $user_details = $self->rest->api_call(
            call => $self->api_calls->{login},
            method => 'POST',
            body => {
                grant_type => 'password',
                platform => 'mobile',
                username => $self->username,
                password => $self->password,
                client_id => $self->client_id,
            }
    );

    $self->access_token($user_details->{access_token});
};

1;
