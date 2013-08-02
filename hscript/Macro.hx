/*
 * Copyright (c) 2011, Nicolas Cannasse
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
package hscript;
import hscript.Expr;
import haxe.macro.Expr;
import Lambda.*;
class Macro {

	var p : Position;
	#if haxe3
	var binops : Map<String,Binop>;
	var unops : Map<String,Unop>;
	#else
	var binops : Hash<Binop>;
	var unops : Hash<Unop>;
	#end

	public function new(pos) {
		p = pos;
		#if haxe3
		binops = new Map();
		unops = new Map();
		#else
		binops = new Hash();
		unops = new Hash();
		#end
		for( c in Type.getEnumConstructs(Binop) ) {
			if( c == "OpAssignOp" ) continue;
			var op = Type.createEnum(Binop, c);
			var assign = false;
			var str = switch( op ) {
			case OpAdd: assign = true;  "+";
			case OpMult: assign = true; "*";
			case OpDiv: assign = true; "/";
			case OpSub: assign = true; "-";
			case OpAssign: "=";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpAnd: assign = true; "&";
			case OpOr: assign = true; "|";
			case OpXor: assign = true; "^";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpShl: assign = true; "<<";
			case OpShr: assign = true; ">>";
			case OpUShr: assign = true; ">>>";
			case OpMod: assign = true; "%";
			case OpAssignOp(_): "";
			case OpInterval: "...";
			#if haxe3
			case OpArrow: "=>";
			#end
			};
			binops.set(str, op);
			if( assign )
				binops.set(str + "=", OpAssignOp(op));
		}
		for( c in Type.getEnumConstructs(Unop) ) {
			var op = Type.createEnum(Unop, c);
			var str = switch( op ) {
			case OpNot: "!";
			case OpNeg: "-";
			case OpNegBits: "~";
			case OpIncrement: "++";
			case OpDecrement: "--";
			}
			unops.set(str, op);
		}
	}
	static inline function map<T, R>(a : Array<T>, f:T -> R) : Array<R> {
		return [for(i in a) f(i)];
	}

	function convertType( t : Expr.CType ) : ComplexType {
		return switch( t ) {
		case CTPath(pack, args):
			var params = [];
			if( args != null )
				for( t in args )
					params.push(TPType(convertType(t)));
			TPath({
				pack : pack,
				name : pack.pop(),
				params : params,
				sub : null,
			});
		case CTParent(t): TParent(convertType(t));
		case CTFun(args, ret):
			TFunction(map(args,convertType), convertType(ret));
		case CTAnon(fields):
			var tf = [];
			for( f in fields )
				tf.push( { name : f.name, meta : [], doc : null, access : [], kind : FVar(convertType(f.t),null), pos : p } );
			TAnonymous(tf);
		};
	}
	function convertField(f:Field):haxe.macro.Expr.Field {
		var f = cl.fields[fk];
		var kind = null, access = [];
		if(f.access.has(Public))
			access.push(APublic);
		if(f.access.has(Private))
			access.push(APrivate);
		if(f.access.has(Static))
			access.push(AStatic);
		kind = if(f.access.has(Function)) {
			switch(f.expr) {
				case EFunction(args, exp, name, ret):
					FieldType.FFun({
						ret: ret == null ? null : convertType(ret),
						args: [for(a in args) {type: a.t == null ? null : convertType(a.t), name: a.name, opt: false}],
						params: [],
						expr: convert(exp)
					});
				default: throw "Invalid class"; 
			}
		} else
			FieldType.FVar(f.type == null ? null : convertType(f.type), f.expr == null ? null : convert(f.expr));
		return {pos: this.p, name:fk, kind: kind, access: access};
	}
	public function convert( e : hscript.Expr ) : Expr {
		return { expr : switch( e  ) {
			case EClassDecl(cl):
				var td:TypeDefinition = {
					pos: this.p,
					name: cl.name,
					meta: [],
					pack: [],
					params: [],
					isExtern: false,
					kind: TypeDefKind.TDClass(),
					fields: [for(fk in cl.fields.keys()) convertField(fk)]
				};
				haxe.macro.Context.defineType(td);
				EConst(CIdent("null"));
			case EConst(c):
				EConst(switch(c) {
					case CInt(v): CInt(Std.string(v));
					case CFloat(f): CFloat(Std.string(f));
					case CString(s): CString(s);
				});
			case EIdent(v):
				EConst(CIdent(v));
			case EVars(vs):
				EVars([for(v in vs) {name: v.name, expr: v.expr == null ? null : convert(v.expr), type: v.type == null ? null : convertType(v.type)}]);
			case EParent(e):
				EParenthesis(convert(e));
			case EBlock(el):
				EBlock(map(el,convert));
			case EField(e, f):
				EField(convert(e), f);
			case EBinop(op, e1, e2):
				var b = binops.get(op);
				if( b == null ) throw EInvalidOp(op);
				EBinop(b, convert(e1), convert(e2));
			case EUnop(op, prefix, e):
				var u = unops.get(op);
				if( u == null ) throw EInvalidOp(op);
				EUnop(u, !prefix, convert(e));
			case ECall(e, params):
				ECall(convert(e), map(params, convert));
			case EIf(c, e1, e2):
				EIf(convert(c), convert(e1), e2 == null ? null : convert(e2));
			case EWhile(c, e):
				EWhile(convert(c), convert(e), true);
			case EFor(v, it, efor):
				var p:haxe.macro.Position = cast p ;
				EFor({ expr : EIn({ expr : EConst(CIdent(v)), pos : p },convert(it)), pos : p }, convert(efor));
			case EBreak:
				EBreak;
			case EContinue:
				EContinue;
			case EFunction(args, e, name, ret):
				var targs = [];
				for( a in args )
					targs.push( {
						name : a.name,
						type : a.t == null ? null : convertType(a.t),
						opt : false,
						value : null,
					});
				EFunction(name, {
					params : [],
					args : targs,
					expr : convert(e),
					ret : ret == null ? null : convertType(ret),
				});
			case EReturn(e):
				EReturn(e == null ? null : convert(e));
			case EArray(e, index):
				EArray(convert(e), convert(index));
			case EArrayDecl(el):
				EArrayDecl(map(el,convert));
			case ENew(cl, params):
				var pack = cl.split(".");
				ENew( { pack : pack, name : pack.pop(), params : [], sub : null }, map(params, convert));
			case EThrow(e):
				EThrow(convert(e));
			case ETry(e, v, t, ec):
				ETry(convert(e), [ { type : convertType(t), name : v, expr : convert(ec) } ]);
			case EObject(fields):
				var tf = [];
				for( f in fields )
					tf.push( { field : f.name, expr : convert(f.e) } );
				EObjectDecl(tf);
			case ETernary(cond, e1, e2):
				ETernary(convert(cond), convert(e1), convert(e2));
			case EUntyped(e):
				EUntyped(convert(e));
			case ESwitch(e, cases, edef):
				ESwitch(convert(e), [for(c in cases) {values: [for(v in c.values) convert(v)], guard: c.guard == null ? null : convert(c.guard), expr: c.expr == null ? null : convert(c.expr)}], edef == null ? null : convert(edef));
		}, pos : p  }
	}

}