=head1 NAME

Open311::Endpoint::Integration::UK::Bromley - Bromley integration set-up

=head1 SYNOPSIS

Bromley will have multiple backends, so is set up as a subclass
of the Multi integration.

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Bromley;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Bromley'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'bromley',
);

=pod

Bromley's two endpoints do not overlap in IDs (one integer, one GUID) or
service codes, so there is no need to prefix them. This code overrides the
default Multi code to not change anything, and cope accordingly.

=cut

sub _map_with_new_id {
    my ($self, $attributes, @results) = @_;
    @results = map {
        my ($name, $result) = @$_;
        $result;
    } @results;
    return @results;
}

my $guid_regex = qr/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

sub _map_from_new_id {
    my ($self, $code, $type) = @_;

    my $integration;
    if ($type eq 'request') {
        if ($code =~ /^\d+$/) {
            $integration = 'Passthrough';
        } elsif ($code =~ /$guid_regex/) {
            $integration = 'Echo';
        }
    } elsif ($type eq 'service') {
        if ($code =~ /^\d+/ || $code eq 'missed') {
            $integration = 'Echo';
        } else {
            $integration = 'Passthrough';
        }
    }
    return ($integration, $code);
}

__PACKAGE__->run_if_script;
