package Net::OpenStack::Compute;
use Any::Moose;

our $VERSION = '1.0001'; # VERSION

use Carp;
use HTTP::Request;
use JSON qw(to_json);
use LWP;
use Net::OpenStack::Compute::Auth;

has auth_url   => (is => 'ro', isa => 'Str', required => 1);
has user       => (is => 'ro', isa => 'Str', required => 1);
has key        => (is => 'ro', isa => 'Str', required => 1);
has project_id => (is => 'ro');
has region     => (is => 'ro');

has _auth => (
    is   => 'rw',
    isa  => 'Net::OpenStack::Compute::Auth',
    lazy => 1,
    default => sub {
        my $self = shift;
        Net::OpenStack::Compute::Auth->new(
            auth_url   => $self->auth_url,
            user       => $self->user,
            password   => $self->key,
            project_id => $self->project_id,
            region     => $self->region,
        );
    },
);

has _base_url => (
    is   => 'ro',
    isa  => 'Str',
    lazy => 1,
    default => sub { shift->_auth->base_url },
);

has _agent => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $agent = LWP::UserAgent->new();
        $agent->default_header(x_auth_token => $self->_auth->token);
        return $agent;
    },
);

sub get_servers {
    my ($self, %params) = @_;
    my $detail = '/detail';
    $detail = '' if exists $params{detail} && !$params{detail};
    my $base_url = $self->_base_url;
    return $self->_agent->get("$base_url/servers$detail")->content;
}

sub get_server {
    my ($self, $id) = @_;
    my $base_url = $self->_base_url;
    return $self->_agent->get("$base_url/servers/$id")->content;
}

sub create_server {
    my ($self, %params) = @_;
    my ($name, $flavor, $image) = @params{qw(name flavor image)};
    croak "name param is required"   unless defined $name;
    croak "flavor param is required" unless defined $flavor;
    croak "image param is required"  unless defined $image;
    my $base_url = $self->_base_url;

    my $res = $self->_agent->post(
        "$base_url/servers",
        content_type => 'application/json',
        Content => to_json({
            server => {
                name      => $name,
                imageRef  => $image,
                flavorRef => $flavor,
            }
        })
    );
    return $res->content;
}

sub delete_server {
    my ($self, $id) = @_;
    my $base_url = $self->_base_url;

    my $req = HTTP::Request->new('DELETE', "$base_url/servers/$id");
    my $res = $self->_agent->request($req);
    return $res->is_success;
}

# ABSTRACT: Bindings for the OpenStack compute api.


1;

__END__
=pod

=head1 NAME

Net::OpenStack::Compute - Bindings for the OpenStack compute api.

=head1 VERSION

version 1.0001

=head1 SYNOPSIS

    use Net::OpenStack::Compute;
    my $compute = Net::OpenStack::Compute->new(
        auth_url   => $auth_url,
        user       => $user,
        key        => $password,
        project_id => $project_id, # Optional
        region     => $egion,      # Optional
    );
    $compute->create_server(name => 's1', flavor => $flav_id, image => $img_id);

=head1 DESCRIPTION

This is the main class responsible for interacting with OpenStack Compute.
Also see L<oscompute> for the command line tool that is a wrapper for this
class.

=head1 METHODS

=head2 get_server

    get_server($id)

=head2 get_servers

    get_servers()
    get_servers(detail => 0)

=head2 create_server

    create_server(name => $name, flavor => $flavor, image => $image)

=head2 delete_server

    delete_server($id)

=head1 AUTHOR

Naveed Massjouni <naveedm9@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Naveed Massjouni.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

