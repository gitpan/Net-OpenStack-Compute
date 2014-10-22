package Net::OpenStack::Compute;
use Any::Moose;
with 'Net::OpenStack::Compute::AuthRole';

our $VERSION = '1.0801'; # VERSION

use Carp;
use HTTP::Request;
use JSON qw(from_json to_json);
use LWP;
use Net::OpenStack::Compute::Auth;

has _auth => (
    is   => 'rw',
    isa  => 'Net::OpenStack::Compute::Auth',
    lazy => 1,
    default => sub {
        my $self = shift;
        return Net::OpenStack::Compute::Auth->new(
            map { $_, $self->$_ } qw(auth_url user password project_id region
                service_name is_rax_auth verify_ssl)
        );
    },
    handles => [qw(base_url token)],
);

has _ua => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $agent = LWP::UserAgent->new(
            ssl_opts => { verify_hostname => $self->verify_ssl });
        $agent->default_header(x_auth_token => $self->token);
        return $agent;
    },
);

sub _get_query {
    my %params = @_;
    my $q = $params{query} or return '';
    for ($q) { s/^/?/ unless /^\?/ }
    return $q;
};

sub get_servers {
    my ($self, %params) = @_;
    my $q = _get_query(%params);
    my $res = $self->_ua->get($self->_url("/servers", $params{detail}, $q));
    return from_json($res->content)->{servers};
}

sub get_server {
    my ($self, $id) = @_;
    croak "Invalid server id" unless $id;
    my $res = $self->_ua->get($self->_url("/servers/$id"));
    return undef unless $res->is_success;
    return from_json($res->content)->{server};
}

sub get_servers_by_name {
    my ($self, $name) = @_;
    my $servers = $self->get_servers(detail => 1);
    return [ grep { $_->{name} eq $name } @$servers ];
}

sub create_server {
    my ($self, $data) = @_;
    croak "invalid data" unless $data and 'HASH' eq ref $data;
    croak "name is required" unless defined $data->{name};
    croak "flavorRef is required" unless defined $data->{flavorRef};
    croak "imageRef is required" unless defined $data->{imageRef};
    my $res = $self->_post("/servers", { server => $data });
    _check_res($res);
    return from_json($res->content)->{server};
}

sub delete_server {
    my ($self, $id) = @_;
    my $req = HTTP::Request->new(DELETE => $self->_url("/servers/$id"));
    my $res = $self->_ua->request($req);
    return _check_res($res);
}

sub rebuild_server {
    my ($self, $server, $data) = @_;
    croak "server id is required" unless $server;
    croak "invalid data" unless $data and 'HASH' eq ref $data;
    croak "imageRef is required" unless $data->{imageRef};
    my $res = $self->_action($server, rebuild => $data);
    _check_res($res);
    return from_json($res->content)->{server};
}

sub resize_server {
    my ($self, $server, $data) = @_;
    croak "server id is required" unless $server;
    croak "invalid data" unless $data and 'HASH' eq ref $data;
    croak "flavorRef is required" unless $data->{flavorRef};
    my $res = $self->_action($server, resize => $data);
    return _check_res($res);
}

sub reboot_server {
    my ($self, $server, $data) = @_;
    croak "server id is required" unless $server;
    croak "invalid data" unless $data and 'HASH' eq ref $data;
    croak "reboot type is required" unless $data->{type};
    my $res = $self->_action($server, reboot => $data);
    return _check_res($res);
}

sub set_password {
    my ($self, $server, $password) = @_;
    croak "server id is required" unless $server;
    croak "password id is required" unless defined $password;
    my $res = $self->_action($server,
        changePassword => { adminPass => $password });
    return _check_res($res);
}

sub get_images {
    my ($self, %params) = @_;
    my $q = _get_query(%params);
    my $res = $self->_ua->get($self->_url("/images", $params{detail}, $q));
    return from_json($res->content)->{images};
}

sub get_image {
    my ($self, $id) = @_;
    my $res = $self->_ua->get($self->_url("/images/$id"));
    return from_json($res->content)->{image};
}

sub create_image {
    my ($self, $server, $data) = @_;
    croak "server id is required" unless defined $server;
    croak "invalid data" unless $data and 'HASH' eq ref $data;
    croak "name is required" unless defined $data->{name};
    my $res = $self->_action($server, createImage => $data);
    return _check_res($res);
}

sub delete_image {
    my ($self, $id) = @_;
    my $req = HTTP::Request->new(DELETE => $self->_url("/images/$id"));
    my $res = $self->_ua->request($req);
    return _check_res($res);
}

sub get_flavors {
    my ($self, %params) = @_;
    my $q = _get_query(%params);
    my $res = $self->_ua->get($self->_url('/flavors', $params{detail}, $q));
    return from_json($res->content)->{flavors};
}

sub get_flavor {
    my ($self, $id) = @_;
    my $res = $self->_ua->get($self->_url("/flavors/$id"));
    return from_json($res->content)->{flavor};
}

sub _url {
    my ($self, $path, $is_detail, $query) = @_;
    my $url = $self->base_url . $path;
    $url .= '/detail' if $is_detail;
    $url .= $query if $query;
    return $url;
}

sub _check_res { croak $_[0]->content unless $_[0]->is_success; return 1; }

sub _post {
    my ($self, $url, $data) = @_;
    return $self->_ua->post(
        $self->_url($url),
        content_type => 'application/json',
        content      => to_json($data),
    );
}

sub _action {
    my ($self, $server, $action, $data) = @_;
    return $self->_post("/servers/$server/action", { $action => $data });
}

# ABSTRACT: Bindings for the OpenStack Compute API.


1;

__END__
=pod

=head1 NAME

Net::OpenStack::Compute - Bindings for the OpenStack Compute API.

=head1 VERSION

version 1.0801

=head1 SYNOPSIS

    use Net::OpenStack::Compute;
    my $compute = Net::OpenStack::Compute->new(
        auth_url     => $auth_url,
        user         => $user,
        password     => $password,
        project_id   => $project_id,
        # Optional:
        region       => $ENV{NOVA_REGION_NAME},
        service_name => $ENV{NOVA_SERVICE_NAME},
        is_rax_auth  => $ENV{NOVA_RAX_AUTH},
        verify_ssl   => 0, 
    );
    $compute->create_server(name => 's1', flavor => $flav_id, image => $img_id);

=head1 DESCRIPTION

This class is an interface to the OpenStack Compute API.
Also see the L<oscompute> command line tool.

=head1 METHODS

Methods that take a hashref data param generally expect the corresponding
data format as defined by the OpenStack API JSON request objects.
See the
L<OpenStack Docs|http://docs.openstack.org/api/openstack-compute/1.1/content>
for more information.
Methods that return a single resource will return false if the resource is not
found.
Methods that return an arrayref of resources will return an empty arrayref if
the list is empty.
Methods that create, modify, or delete resources will throw an exception on
failure.

=head2 get_server

    get_server($id)

Returns the server with the given id or false if it doesn't exist.

=head2 get_servers

    get_servers(%params)

params:

=over

=item detail

Optional. Defaults to 0.

=item query

Optional query string to be appended to requests.

=back

Returns an arrayref of all the servers.

=head2 get_servers_by_name

    get_servers_by_name($name)

Returns an arrayref of servers with the given name.
Returns an empty arrayref if there are no such servers.

=head2 create_server

    create_server({ name => $name, flavorRef => $flavor, imageRef => $img_id })

Returns a server hashref.

=head2 delete_server

    delete_server($id)

Returns true on success.

=head2 rebuild_server

    rebuild_server($server_id, { imageRef => $img_id })

Returns a server hashref.

=head2 set_password

    set_password($server_id, $new_password)

Returns true on success.

=head2 get_image

    get_image($id)

Returns an image hashref.

=head2 get_images

    get_images()

params:

=over

=item detail

Optional. Defaults to 0.

=item query

Optional query string to be appended to requests.

=back

Returns an arrayref of all the images.

=head2 create_image

    create_image($server_id, { name => 'bob' })

Returns an image hashref.

=head2 delete_image

    delete_image($id)

Returns true on success.

=head2 get_flavor

    get_flavor($id)

Returns a flavor hashref.

=head2 get_flavors

    get_flavors()

params:

=over

=item detail

Optional. Defaults to 0.

=item query

Optional query string to be appended to requests.

=back

Returns an arrayref of all the flavors.

=head2 token

    token()

Returns the OpenStack Compute API auth token.

=head2 base_url

    base_url()

Returns the base url for the OpenStack Compute API, which is returned by the
server after authenticating.

=head1 SEE ALSO

=over

=item L<oscompute>

=item L<OpenStack Docs|http://docs.openstack.org/api/openstack-compute/1.1/content>

=back

=head1 AUTHOR

Naveed Massjouni <naveedm9@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Naveed Massjouni.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

