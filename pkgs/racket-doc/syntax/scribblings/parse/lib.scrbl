#lang scribble/doc
@(require (for-syntax racket/base)
          syntax/parse/define
          scribble/manual
          scribble/struct
          scribble/decode
          scribble/eval
          "../common.rkt"
          "parse-common.rkt"
          (for-label racket/base racket/contract racket/syntax
                     syntax/kerncase syntax/parse/lib/function-header))

@(define the-eval (make-sp-eval))
@(the-eval '(require syntax/parse/lib/function-header))

@title{Library Syntax Classes and Literal Sets}

@section{Syntax Classes}

@(begin
   (begin-for-syntax
     (define-splicing-syntax-class stxclass-option
       #:attributes (type)
       (pattern {~seq #:splicing}
                #:with type #'"splicing syntax class")
       (pattern {~seq}
                #:with type #'"syntax class")))
   (define-syntax-parser defstxclass
     [(_ name:id :stxclass-option . pre-flows)
      #'(defidform #:kind type name . pre-flows)]
     [(_ datum . pre-flows)
      #'(defproc #:kind "syntax class" datum @#,tech{syntax class} . pre-flows)])
   (define-syntax-parser defattribute
     [(_ name:id . pre-flows)
      #'(subdefthing #:kind "attribute" #:link-target? #f name
        . pre-flows)]))

@defstxclass[expr]{

Matches anything except a keyword literal (to distinguish expressions
from the start of a keyword argument sequence). The term is not
otherwise inspected, since it is not feasible to check if it is
actually a valid expression.
}

@deftogether[(
@defstxclass[identifier]
@defstxclass[boolean]
@defstxclass[char]
@defstxclass[keyword]
@defstxclass[number]
@defstxclass[integer]
@defstxclass[exact-integer]
@defstxclass[exact-nonnegative-integer]
@defstxclass[exact-positive-integer]
@defstxclass[regexp]
@defstxclass[byte-regexp])]{

Match syntax satisfying the corresponding predicates.
}

@deftogether[[
@defidform[#:kind "syntax class" #:link-target? #f
           string]
@defidform[#:kind "syntax class" #:link-target? #f
           bytes]
]]{

As special cases, Racket's @racket[string] and @racket[bytes] bindings
are also interpreted as syntax classes that recognize literal strings
and bytes, respectively.

@history[#:added "6.9.0.4"]
}

@defstxclass[id]{ Alias for @racket[identifier]. }
@defstxclass[nat]{ Alias for @racket[exact-nonnegative-integer]. }
@defstxclass[str]{ Alias for @racket[string]. }
@defstxclass[character]{ Alias for @racket[char]. }

@defstxclass[(static [predicate (-> any/c any/c)]
                     [description (or/c string? #f)])]{

The @racket[static] syntax class matches an
identifier that is bound in the syntactic environment to static
information (see @racket[syntax-local-value]) satisfying the given
@racket[predicate]. If the term does not match, the
@racket[description] argument is used to describe the expected syntax.

When used outside of the dynamic extent of a macro transformer (see
@racket[syntax-transforming?]), matching fails.

The attribute @var[value] contains the value the name is bound to.

If matching succeeds, @racket[static] additionally adds the matched identifier
to the current @racket[syntax-parse] state under the key @racket['literals]
using @racket[syntax-parse-state-cons!], in the same way as identifiers matched
using @racket[#:literals] or @racket[~literal].

@history[#:changed "6.90.0.29"
         @elem{Changed to add matched identifiers to the @racket[syntax-parse]
               state under the key @racket['literals].}]}

@defstxclass[(expr/c [contract-expr syntax?]
                     [#:arg? arg? any/c #t]
                     [#:positive pos-blame
                      (or/c syntax? string? module-path-index? 'from-macro 'use-site 'unknown)
                      'from-macro]
                     [#:negative neg-blame
                      (or/c syntax? string? module-path-index? 'from-macro 'use-site 'unknown)
                      'use-site]
                     [#:name expr-name (or/c identifier? string? symbol?) #f]
                     [#:macro macro-name (or/c identifier? string? symbol?) #f]
                     [#:context context (or/c syntax? #f) #, @elem{determined automatically}]
                     [#:phase phase exact-integer? (syntax-local-phase-level)])]{

Accepts an expression (@racket[expr]) and computes an attribute
@racket[c] that represents the expression wrapped with the contract
represented by @racket[contract-expr]. Note that
@racket[contract-expr] is potentially evaluated each time the code
generated by the macro is run; for the best performance,
@racket[contract-expr] should be a variable reference.

The positive blame represents the obligations of the macro imposing
the contract---the ultimate user of @racket[expr/c].  The contract's
negative blame represents the obligations of the expression being
wrapped.  By default, the positive blame is inferred from the
definition site of the macro (itself inferred from the
@racket[context] argument), and the negative blame is taken as the
module currently being expanded, but both blame locations can be
overridden. When @racket[arg?] is @racket[#t], the term being matched
is interpreted as an argument (that is, coming from the negative
party); when @racket[arg?] is @racket[#f], the term being matched is
interpreted as a result of the macro (that is, coming from the
positive party).

The @racket[pos-blame] and @racket[neg-blame] arguments are turned
into blame locations as follows:
@itemize[
@item{If the argument is a string, it is used directly as the blame
  label.}
@item{If the argument is syntax, its source location is used
  to produce the blame label.}
@item{If the argument is a module path index, its resolved module path
  is used.}
@item{If the argument is @racket['from-macro], the macro is inferred
  from either the @racket[macro-name] argument (if @racket[macro-name]
  is an identifier) or the @racket[context] argument, and the module
  where it is @emph{defined} is used as the blame location. If
  neither an identifier @racket[macro-name] nor a @racket[context]
  argument is given, the location is @racket["unknown"].}
@item{If the argument is @racket['use-site], the module being
  expanded is used.}
@item{If the argument is @racket['unknown], the blame label is
  @racket["unknown"].}
]

The @racket[macro-name] argument is used to determine the macro's
binding, if it is an identifier. If @racket[expr-name] is given,
@racket[macro-name] is also included in the contract error message. If
@racket[macro-name] is omitted or @racket[#f], but @racket[context] is
a syntax object, then @racket[macro-name] is determined from
@racket[context].

If @racket[expr-name] is not @racket[#f], it is used in the contract's
error message to describe the expression the contract is applied to.

The @racket[context] argument is used, when necessary, to infer the
macro name for the negative blame party and the contract error
message. The @racket[context] should be either an identifier or a
syntax pair with an identifier in operator position; in either case,
that identifier is taken as the macro ultimately requesting the
contract wrapping.

The @racket[phase] argument must indicate the @tech[#:doc
refman]{phase level} at which the contracted expression will be
evaluated. Using the contracted expression at a different phase level
will cause a syntax error because it will contain introduced
references bound in the wrong phase. In particular:
@itemlist[

@item{Use the default value, @racket[(syntax-local-phase-level)], when
the contracted expression will be evaluated at the same phase as the
form currently being expanded. This is usually the case.}

@item{Use @racket[(add1 (syntax-local-phase-level))] in cases such as
the following: the contracted expression will be placed inside a
@racket[begin-for-syntax] form, used in the right-hand side of a
@racket[define-syntax] or @racket[let-syntax] form, or passed to
@racket[syntax-local-bind-syntaxes] or @racket[syntax-local-eval].}

]
Any phase level other than @racket[#f] (the @tech[#:doc refman]{label
phase level}) is allowed, but phases other than
@racket[(syntax-local-phase-level)] and @racket[(add1
(syntax-local-phase-level))] may only be used when in the dynamic
extent of a @tech[#:doc refman]{syntax transformer} or while a module
is being @tech[#:doc refman]{visit}ed (see
@racket[syntax-transforming?]), otherwise @racket[exn:fail:contract?]
is raised.

See @secref{exprc} for examples.

@bold{Important:} Make sure when using @racket[expr/c] to use the
@racket[c] attribute. The @racket[expr/c] syntax class does not change how
pattern variables are bound; it only computes an attribute that
represents the checked expression.

@history[
#:changed "7.2.0.3" @elem{Added the @racket[#:arg?] keyword
argument and changed the default values and interpretation of the
@racket[#:positive] and @racket[#:negative] arguments.}
#:changed "7.3.0.3" @elem{Added the @racket[#:phase] keyword argument.}]}


@section{Literal Sets}

@defidform[kernel-literals]{

Literal set containing the identifiers for fully-expanded code
(@secref[#:doc '(lib "scribblings/reference/reference.scrbl")
"fully-expanded"]). The set contains all of the forms listed by
@racket[kernel-form-identifier-list], plus @racket[module],
@racket[#%plain-module-begin], @racket[#%require], and
@racket[#%provide].

Note that the literal-set uses the names @racket[#%plain-lambda] and
@racket[#%plain-app], not @racket[lambda] and @racket[#%app].
}

@section{Function Headers}
@defmodule[syntax/parse/lib/function-header]

@defstxclass[function-header]{
 Matches a name and formals found in function header.
 It also supports the curried function shorthand.
 @defattribute[name syntax?]{
  The name part in the function header.
 }
 @defattribute[params syntax?]{
  The list of parameters in the function header.
 }
}
@defstxclass[formal #:splicing]{
 Matches a single formal that can be used in a function header.
 @defattribute[name syntax?]{
  The name part in the formal.
 }
 @defattribute[kw (or/c syntax? #f)]{
  The keyword part in the formal, if it exists.
 }
 @defattribute[default (or/c syntax? #f)]{
  The default expression part in the formal, if it exists.
 }
}
@defstxclass[formals]{
 Matches a list of formals that would be used in a function header.
 @defattribute[params syntax?]{
  The list of parameters in the formals.
 }
}

@interaction[#:eval the-eval
(syntax-parse #'(define ((foo x) y) 1)
  [(_ header:function-header body ...+) #'(header header.name header.params)])
(syntax-parse #'(lambda xs xs)
  [(_ fmls:formals body ...+) #'(fmls fmls.params)])
(syntax-parse #'(lambda (x y #:kw [kw 42] . xs) xs)
  [(_ fmls:formals body ...+) #'(fmls fmls.params)])
(syntax-parse #'(lambda (x) x)
  [(_ (fml:formal) body ...+) #'(fml
                                 fml.name
                                 (~? fml.kw #f)
                                 (~? fml.default #f))])
(syntax-parse #'(lambda (#:kw [kw 42]) kw)
  [(_ (fml:formal) body ...+) #'(fml fml.name fml.kw fml.default)])
]