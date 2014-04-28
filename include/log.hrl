%%
%% Log macros
%%
-ifndef(__LOG_HRL__).
-define(__LOG_HRL__, true).

-include_lib("eunit/include/eunit.hrl").

-ifdef(EUNIT).

-define(fmt_str(Fmt),
        if is_binary(Fmt) == true -> << ?MODULE_STRING,$:,(integer_to_binary(?LINE))/binary," ",(Fmt)/binary,$\n >>;
           true -> (?MODULE_STRING ":? " Fmt "\n")
        end).

-define(debug(Fmt), ?debugFmt(Fmt, [])).
-define(debug(Fmt, Args), ?debugFmt(Fmt, Args)).
-define(debug(_Attrs, Fmt, Args), ?debugFmt(Fmt, Args)).

-define(info(Fmt), error_logger:info_msg(?fmt_str(Fmt), [])).
-define(info(Fmt, Args), error_logger:info_msg(?fmt_str(Fmt), Args)).
-define(info(_Attrs, Fmt, Args), error_logger:info_msg(?fmt_str(Fmt), Args)).

-define(notice(Fmt), error_logger:info_msg(?fmt_str(Fmt), [])).
-define(notice(Fmt, Args), error_logger:info_msg(?fmt_str(Fmt), Args)).
-define(notice(_Attrs, Fmt, Args), error_logger:info_msg(?fmt_str(Fmt), Args)).

-define(warning(Fmt), error_logger:warning_msg(?fmt_str(Fmt), [])).
-define(warning(Fmt, Args), error_logger:warning_msg(?fmt_str(Fmt), Args)).
-define(warning(_Attrs, Fmt, Args), error_logger:warning_msg(?fmt_str(Fmt), Args)).

-define(error(Fmt), error_logger:error_msg(?fmt_str(Fmt), [])).
-define(error(Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).
-define(error(_Attrs, Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).

-define(critical(Fmt), error_logger:error_msg(?fmt_str(Fmt), [])).
-define(critical(Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).
-define(critical(_Attrs, Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).

-define(alert(Fmt), error_logger:error_msg(?fmt_str(Fmt), [])).
-define(alert(Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).
-define(alert(_Attrs, Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).

-define(emergency(Fmt), error_logger:error_msg(?fmt_str(Fmt), [])).
-define(emergency(Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).
-define(emergency(_Attrs, Fmt, Args), error_logger:error_msg(?fmt_str(Fmt), Args)).

-else.

-compile({parse_transform, lager_transform}).


-define(debug(Fmt), lager:debug(Fmt)).
-define(debug(Fmt, Args), lager:debug(Fmt, Args)).
-define(debug(Attrs, Fmt, Args), lager:debug(Attrs, Fmt, Args)).

-define(info(Fmt), lager:info(Fmt)).
-define(info(Fmt, Args), lager:info(Fmt, Args)).
-define(info(Attrs, Fmt, Args), lager:info(Attrs, Fmt, Args)).

-define(notice(Fmt), lager:notice(Fmt)).
-define(notice(Fmt, Args), lager:notice(Fmt, Args)).
-define(notice(Attrs, Fmt, Args), lager:notice(Attrs, Fmt, Args)).

-define(warning(Fmt), lager:warning(Fmt)).
-define(warning(Fmt, Args), lager:warning(Fmt, Args)).
-define(warning(Attrs, Fmt, Args), lager:warning(Attrs, Fmt, Args)).

-define(error(Fmt), lager:error(Fmt)).
-define(error(Fmt, Args), lager:error(Fmt, Args)).
-define(error(Attrs, Fmt, Args), lager:error(Attrs, Fmt, Args)).

-define(critical(Fmt), lager:critical(Fmt)).
-define(critical(Fmt, Args), lager:critical(Fmt, Args)).
-define(critical(Attrs, Fmt, Args), lager:critical(Attrs, Fmt, Args)).

-define(alert(Fmt), lager:alert(Fmt)).
-define(alert(Fmt, Args), lager:alert(Fmt, Args)).
-define(alert(Attrs, Fmt, Args), lager:alert(Attrs, Fmt, Args)).

-define(emergency(Fmt), lager:emergency(Fmt)).
-define(emergency(Fmt, Args), lager:emergency(Fmt, Args)).
-define(emergency(Attrs, Fmt, Args), lager:emergency(Attrs, Fmt, Args)).

-endif.

-endif.
