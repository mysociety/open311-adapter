=head1 NAME

Open311::Endpoint::Integration::UK::Merton - Merton integration set-up

=head1 SYNOPSIS

Merton has multiple backends, so is set up as a subclass
of the Multi integration.

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Merton;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Merton'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'merton',
);

=pod

Merton has three endpoints; a passthrough, Echo and Ezytreev.

This code overrides the default Multi code to only use prefixing
where we need it.

No prefixing is applied for request IDs:
* GUIDs are always Echo.
* Ezytreev ones are already prefixed with 'ezytreev'.
* The rest we assume are passthrough.

For service codes:
* Numbers or the text 'missed' are Echo.
* We prefix Ezytreev ones to start with 'Ezytreev-' like a normal endpoint behind multi.
* The rest we assume are passthrough.

=cut

sub _map_with_new_id {
    my ($self, $attributes, @results) = @_;
    $attributes = [$attributes] unless ref $attributes eq 'ARRAY';
    return map {
        my ($name, $result)  = @$_;
        if ($name eq 'Ezytreev' && grep(/^service_code$/, @$attributes)) {
            # Apply normal mapping to Ezytreev service codes.
            my @updated_results = $self->SUPER::_map_with_new_id($attributes, $_);
            $updated_results[0];
        } else {
            # Leave rest unchanged.
            $result;
        }
    } @results;
}

my $guid_regex = qr/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

sub _map_from_new_id {
    my ($self, $code, $type) = @_;

    my $integration;
    if ($type eq 'request') {
        if ($code =~ /^ezytreev-/) {
            $integration = 'Ezytreev';
        } elsif ($code =~ /$guid_regex/) {
            $integration = 'Echo';
        } else {
            $integration = 'Passthrough';
        }
    } elsif ($type eq 'service') {
        if ($code =~ /^Ezytreev-/) {
            $code =~ s/^Ezytreev-//;
            $integration = 'Ezytreev';
        } elsif ($code =~ /^\d+/ || $code eq 'missed') {
            $integration = 'Echo';
        } else {
            $integration = 'Passthrough';
        }
    } elsif ($type eq 'token') {
        # Echo and Ezytreev do not use tokens
        $integration = 'Passthrough';
    }
    return ($integration, $code);
}

__PACKAGE__->run_if_script;
