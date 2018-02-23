package Integrations::Confirm::BANES;

use Moo;
extends 'Integrations::Confirm';
with 'Role::Config';

sub endpoint_url { $_[0]->config->{CONFIRM}->{BANES}->{url} }

sub credentials {
    my $config = $_[0]->config->{CONFIRM}->{BANES};
    return (
        $config->{username},
        $config->{password},
        $config->{tenant_id}
    );
}

has '+server_timezone' => (
    default => 'Europe/London',
);

has '+memcache_namespace'  => (
    default => 'banes_confirm',
);

has '+enquiry_method_code'  => (
    default => 'WB' # 'Web Submission' is the EnquiryMethodName
);

has '+point_of_contact_code'  => (
    default => 'CC' # 'Contact Centre' is the PointOfContactName
);


1;
