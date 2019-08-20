package Integrations::SalesForce::Rutland;

use Moo;
extends 'Integrations::SalesForce';
with 'Role::Config';

has '+endpoint_url' => (
    default => sub { $_[0]->config->{Rutland}->{endpoint} || '' }
);

has '+credentials' => (
    default => sub { $_[0]->config->{Rutland}->{credentials} || {} }
);

1;
