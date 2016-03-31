use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new;
my $uri = 'http://localhost:8080';

$t->get_ok($uri)->status_is(200);

$t->get_ok($uri . '/authorised')->status_is(403);

$t->post_ok($uri . '/authenticate.json'=> json => {'u' => 'test1', 'p' =>'test'})->status_is(200);
$t->get_ok($uri . '/authorised')->status_is(200);

$t->get_ok($uri . '/api/templates.json')->status_is(200)->json_is({foo => bar});


done_testing;
