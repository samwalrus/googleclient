:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_error)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_session)).
:- use_module(library(http/js_write)).
:- use_module(library(http/http_files)).
:- use_module(library(http/json)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_ssl_plugin)).

:- use_module('../prolog/google_client').

http:location(files, '/f', []).

:- http_handler('/', home_page, []).
:- http_handler('/gconnect', gconnect, []).

:- http_handler(files(.), http_reply_from_files('test_files', []), [prefix]).

:- dynamic
	my_code/1.
server :-
	server(5000).

server(Port) :-
        http_server(http_dispatch, [port(Port)]),
	format("Server should be on port 5000 to work with google settings- is it?").

read_client_secrets(MyWeb,Client_Id,Client_Secret) :-
	open('client_secrets.json',read,Stream),
	json_read_dict(Stream,Dict),
	_{web:MyWeb} :< Dict,
	_{
	    auth_provider_x509_cert_url:Auth_url,
	    auth_uri:Auth_uri,
	    client_email:Client_email,
	    client_id:Client_Id,
	    client_secret:Client_Secret,
	    client_x509_cert_url:Client_cert_url,
	    javascript_origins:Javascript_origins,
	    redirect_uris: Redirect_uris,
	    token_uri:Token_Uri
	} :<MyWeb,
	close(Stream).



post_to_google(Profile,Code,CID,CS):-

	ListofData=[
		       code=Code,
		       client_id=CID,
		       client_secret=CS,
		       redirect_uri='postmessage',
		       grant_type=authorization_code

			  ],
        http_open('https://www.googleapis.com/oauth2/v3/token', In,
                  [ status_code(_ErrorCode),
		    method(post),post(form(ListofData))
                  ]),
	call_cleanup(json_read_dict(In, Profile),
		     close(In)).


%cert_verify(_SSL, _ProblemCert, _AllCerts, _FirstCert, _Error) :-
 %       debug(ssl(cert_verify),'~s', ['Accepting certificate']).



home_page(Request) :-
	nick_name(Nick),
	reply_html_page(
	   [title('Oauth Test'),
	   script([type='text/javascript',
		    src='//ajax.googleapis.com/ajax/libs/jquery/1.8.2/jquery.min.js'],[]),
	   script([type='text/javascript',
		    src='//apis.google.com/js/platform.js?onload=start'],[]),
	   \call_back_script
	   ],
	    [h1('hello'),
	    p('~w, we are glad your spirit is present with us'-[Nick]),
	    \google_loginButton
	    ]).

gconnect(Request):-
	%I need to get the code from the request
	http_parameters(Request,[code(Code,[default(default)])]),
	read_client_secrets(_MyWeb,Client_Id,Client_Secret),
	post_to_google(Credentials,Code,Client_Id,Client_Secret),
	exchange_token_for_details(Credentials,Result),
	trace,
	Result = Frog,
	reply_json(Credentials).


%If there is an error
exchange_token_for_details(Credentials,Error):-
	check_json_for_error(Credentials,Error).


exchange_token_for_details(Credentials,Check_Result):-
	_{
	    access_token: AccessToken,
	    expires_in: Expires_In,
	    id_token: Id_token,
	    refresh_token: Refresh_Token,
	    token_type: Token_Type
	} :<Credentials,
	check_token_is_valid(AccessToken,Id_token,Check_Result).


check_token_is_valid(AccessToken,Id_token,Check_Result):-
	string_concat("https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=", AccessToken, URL_to_Check_Token),
	http_open(URL_to_Check_Token, In,
                  [ status_code(_ErrorCode)

                  ]),
	call_cleanup(json_read_dict(In, Check_Result),
	\+ check_json_for_error(Check_Result,_Error),
	close(In)),
	trace,
	%in Check result is there a user_id? compare this to Object sub
	compare_id_tokens(Check_Result,Id_token),
        %issued_to from check_result should be the same as clien_id from client_secrets file.
	compare_client_ids(Check_Result).
        %check to see if they are logged in already?

compare_client_ids(Check_Result):-
	_{issued_to:Issued_To}:<Check_Result,
	read_client_secrets(_MyWeb,Client_Id,_Client_Secret),
	Issued_To = Client_Id.


compare_id_tokens(Check_Result,Id_token):-
	jwt(Id_token,Object),
	_{sub:Object_Id}:<Object,
	_{user_id:User_Id}:<Check_Result,
	Object_Id =User_Id.

check_json_for_error(Json,Error):-
	_{
	    error: Error
	  } :<Json.


jwt(String, Object) :-
	nonvar(String),
	split_string(String, ".", "", [Header64,Object64|_Parts]),
	base64url_json(Header64, _Header),
	base64url_json(Object64, Object).

%%	base64url_json(+String, -JSONDict) is semidet.
%
%	True when JSONDict is represented  in   the  Base64URL and UTF-8
%	encoded String.

base64url_json(String, JSON) :-
	string_codes(String, Codes),
	phrase(base64url(Bytes), Codes),
	phrase(utf8_codes(Text), Bytes),
	setup_call_cleanup(
	    open_codes_stream(Text, Stream),
	    json_read_dict(Stream, JSON),
	    close(Stream)).





call_back_script -->
	js_script({|javascript||
		      console.log("script runs");
		      function signInCallback(authResult) {
                        console.log("got to call back");
                        if (authResult['code']) {
                         console.log("has code");
                         console.log(authResult['code']);
			 $('#signInButton').attr('style','display: none');

			 $.post("/gconnect",
			   {code:authResult['code']},
			   function(data,status){
			    //console.log("Data: " + data.reply + "\nStatus: " + status);
			    console.log("Access Token: " + data.access_token + "\nExpires in : " + data.expires_in + "\nToken_type : " + data.token_type +  "\nStatus: " + status);
			   });
			 /*
			 $.ajax({
			       type: 'POST',
			       url: '/gconnect',
			       processData:false,
			       //contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
			       contentType: 'application/octet-stream; charset=utf-8',
			       data: {code:authResult['code']},
			       success: function(result){
					    console.log("success");
					    console.log(result);
					}
			   });
                          */

			}
		      }

		      |}).


google_loginButton -->
	html([div([id="signInButton"],[
		  span([
		     class="g-signin",
		     data-scope="openid email",
		     data-clientid="124024716168-p5lvtlj5jinp9u912s3f7v3a5cuvj2g8.apps.googleusercontent.com",
		     data-redirecturi="postmessage",
		     data-accesstype="offline",
		     data-cookiepolicy="single_host_origin",
		     data-callback="signInCallback",
		     data-approvalprompt="force"],[])
		  ])]).


nick_name(Nick) :-
	http_session_data(nick_name(Nick)),!.

nick_name(Nick) :-
	nick_list(NickList),
	random_member(Nick, NickList),
	http_session_assert(nick_name(Nick)).

nick_list([
    'Gentle One',
    'Blessed Spirit',
    'Wise Soul',
    'Wise One',
    'Beloved Friend'
	  ]).


