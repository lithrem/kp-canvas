#!/usr/bin/perl
#
# Copyright (C) 2013-2014   Ian Firns   <firnsy@kororaproject.org>
#                           Chris Smart <csmart@kororaproject.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Canvas;

use warnings;
use strict;

use Mojo::Base 'Mojolicious';

#
# PERL INCLUDES
#
use Data::Dumper;

use Mojo::ByteStream;
use Mojo::JSON;
use Mojo::Pg;
use Mojolicious::Plugin::Authentication;
use Mojolicious::Plugin::RenderSteps;

use POSIX qw(floor);
use Time::Piece;

#
# LOCAL INCLUDES
#
use Canvas::Model::Machines;
use Canvas::Model::Templates;

#
# CONSTANTS
#
use constant {
  DEBUG   => 1
};


#
# INITIALISE
#
sub startup {
  my $self = shift;

  #
  # CONFIGURATION
  my $config = $self->plugin('JSONConfig' => {file => './canvas.conf'});

  # set the secret
  die "Ensure secrets are specified in config." unless ref $config->{secret} eq 'ARRAY';
  $self->secrets( $config->{secret} );

  #
  # HYPNOTOAD
  $self->app->config(hypnotoad => $config->{hypnotoad} // {} );

  #
  # OAUTH2
  $self->plugin(OAuth2 => $config->{oauth2} // {} );

  # set default session expiration to 4 hours
  $self->sessions->default_expiration(14400);

  #
  # OAUTH
  $self->plugin('OAuth2' => $config->{oauth2} // {});
  $self->plugin('RenderSteps');

  #
  # AUTHENTICATION
  $self->app->log->info('Loading authentication handler.');
  $self->plugin('Authentication' => {
    autoload_user   => 0,
    current_user_fn => 'auth_user',
    load_user => sub {
      my ($app, $user) = @_;

      my $user_hash = $app->pg->db->query("SELECT * FROM users WHERE username=?", $user)->hash // {};

      # load metadata
      if ($user_hash->{id}) {
        $user_hash->{meta} = {};

        $user_hash->{oauth} = $app->session('oauth') // {};

        my $key_values = $app->pg->db->query("SELECT meta_key AS key, array_agg(meta_value) AS values FROM usermeta where user_id=? GROUP BY meta_key", $user_hash->{id})->hashes // {};

        $key_values->each(sub {
          my $e = shift;
          $user_hash->{meta}{$e->{key}} = $e->{values};
        });
      }

      return $user_hash;
    },
    validate_user => sub {
      my ($app, $user, $pass, $extra) = @_;

      # check user pass
      if ($user and $pass) {
        my $u = $app->pg->db->query("SELECT username, password FROM users WHERE username=? AND status='active'", $user)->hash;

        return $u->{username} if $app->users->validate($u, $pass);
      }
      # check github
      elsif (my $github = $extra->{github}) {
        my $u = $app->pg->db->query("SELECT u.username FROM users u JOIN usermeta um ON (um.user_id=u.id) WHERE um.meta_key='oauth_github' AND um.meta_value=? AND u.status='active'", $github->{login})->hash;

        return $u->{username} if $u;
      }
      # check activation
      elsif (my $activated = $extra->{activated}) {
        my $u = $app->pg->db->query("SELECT username FROM users WHERE username=? AND status='active'", $activated->{username})->hash;

        return $u->{username} if $u;
      }

      return undef;
    },
  });

  #
  # MAIL
  unless ($config->{mail} && ($config->{mail}{mode} // '') eq 'production') {
    $self->app->log->info('Loading dummy mail handler for non-production testing.');

    $self->helper('mail' => sub {
      shift->app->log->debug('Sending MOCK email ' . join "\n", @_);
    });
  }
  else {
    #$self->app->log->info('Loading production mail (GMail) handler.');
    #$self->plugin('gmail' => {type => 'text/plain'});
    $self->app->log->info('Loading production mail handler.');
    $self->plugin('mail' => {type => 'text/plain'});
  }

  #
  # HELPERS
  $self->app->log->info('Loading page helpers.');

  $self->plugin('Canvas::Helpers');
  #$self->plugin('Canvas::Helpers::Profile');
  $self->plugin('Canvas::Helpers::User');

  #
  # MODEL
  $self->helper(pg => sub {
    state $pg = Mojo::Pg->new($config->{database}{uri});
  });

  $self->helper('canvas.machines' => sub {
    state $posts = Canvas::Model::Machines->new(pg => shift->pg)
  });
  $self->helper('canvas.templates' => sub {
    state $posts = Canvas::Model::Templates->new(pg => shift->pg)
  });

  #
  # ROUTES
  my $r = $self->routes;

  #
  # CANVAS API ROUTES
  my $r_api = $r->under('/api');

  $r_api->get('/templates')->to('api#templates_get');
  $r_api->post('/templates')->to('api#templates_post');
  $r_api->get('/template/:uuid')->to('api#template_get');
  $r_api->put('/template/:uuid')->to('api#template_update');
  $r_api->delete('/template/:uuid')->to('api#template_del');


  $r_api->get('/machines')->to('api#machines_get');
  $r_api->post('/machines')->to('api#machines_post');
  $r_api->get('/machine/:uuid')->to('api#machine_get');
  $r_api->get('/machine/:uuid/sync')->to('api#machine_sync');
  $r_api->put('/machine/:uuid')->to('api#machine_update');
  $r_api->delete('/machine/:uuid')->to('api#machine_del');


  #
  # PRIMARY ROUTES

  # exception/not_found
  $r->get('/404')->to('api#not_found_get');
  $r->get('/500')->to('api#exception_get');

  # authentication and registration
  $r->any('/authenticate')->to('api#authenticate_any');
  $r->any('/deauthenticate')->to('api#deauthenticate_any');
  $r->any('/authorised')->to('api#authorised_any');

  #
  $r->get('/')->to('api#alpha');

  $r->get('/main')->to('api#index');

  $r->get('/templates')->to('template#index_get');

  $r->get('/:user/templates')->to('template#user_get');
  $r->get('/:user/template')->to('template#summary_get');
  $r->get('/:user/template/:name')->to('template#detail_get');

#  $r->get('/:user/machines')->to('machine#user_get');
#  $r->get('/:user/machine')->to('machine#summary_get');
#  $r->get('/:user/machine/:name')->to('machine#detail_get');

  $r->any('/*trap' => {trap => ''} => sub { shift->redirect_to('/'); });
}

1;
