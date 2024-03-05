package haxe.ui.macros.helpers;

import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.Ref;
import haxe.macro.TypeTools;

using Lambda;

class ClassBuilder {
    public var fields:Array<Field>;
    public var type:haxe.macro.Type;
    public var classType:ClassType;
    public var pos:Position;

    public function new(fields:Array<Field> = null, type:haxe.macro.Type = null, pos:Position = null) {
        this.fields = fields;
        this.type = type;
        if (type != null) {
            try {
                #if macro
                this.classType = TypeTools.getClass(type);
                #else
                this.classType = null;
                #end
            } catch (e:Dynamic) {}
        }
        this.pos = pos;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // General
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    public var vars(get, null):Array<FieldBuilder>;
    private function get_vars():Array<FieldBuilder> {
        var r = [];
        for (f in fields) {
            switch (f.kind) {
                case FVar(_, _):
                    r.push(new FieldBuilder(f, this));
                case _:
            }
        }
        return r;
    }

    public var complexType(get, null):ComplexType;
    private function get_complexType():ComplexType {
        return TypeTools.toComplexType(type);
    }

    public var typePath(get, null):TypePath;
    private function get_typePath():TypePath {
        return switch (complexType) {
            case TPath(p): p;
            case _: null;
        }
    }

    public var fullPath(get, null):String;
    private function get_fullPath():String {
        #if macro
        var s = TypeTools.toString(type);
        var n = s.indexOf("<");
        if (n != -1) {
            s = s.substring(0, n);
        }
        return s;
        #else
        return null;
        #end
    }

    public var name(get, null):String;
    private function get_name():String {
        var fullPathCopy = fullPath;
        var n1 = fullPathCopy.indexOf("<");
        var n2 = fullPathCopy.indexOf(">");
        if (n1 != -1 && n2 != -1) {
            fullPathCopy = fullPathCopy.substring(0, n1) + fullPathCopy.substring(n2 + 1);
        }
        
        return fullPathCopy.split(".").pop();
    }
    
    public var pkg(get, null):Array<String>;
    private function get_pkg():Array<String> {
        var fullPathCopy = fullPath;
        var n1 = fullPathCopy.indexOf("<");
        var n2 = fullPathCopy.indexOf(">");
        if (n1 != -1 && n2 != -1) {
            fullPathCopy = fullPathCopy.substring(0, n1) + fullPathCopy.substring(n2 + 1);
        }
        var parts = fullPathCopy.split(".");
        parts.pop();
        return parts;
    }

    public var isPrivate(get, null):Bool;
    private function get_isPrivate():Bool {
        return switch (type) {
            case TInst(c, _):
                c.get().isPrivate || c.get().meta.has(":noCompletion");
            case TType(tt, _):
                return tt.get().meta.has(":noCompletion");
            case _:
                false;
        }
    }
    
    public var isInterface(get, null):Bool;
    private function get_isInterface():Bool {
        return switch (type) {
            case TInst(c, _):
                c.get().isInterface;
            case _:
                false;
        }
    }
    
    public var isAbstractClass(get, null):Bool;
    private function get_isAbstractClass():Bool {
        return #if (haxe_ver >= 4.2) classType.isAbstract #else false #end;
    }

    public function findField(name:String):Field {
        var r = null;
        if (fields != null) {
            for (f in fields) {
                if (f.name == name) {
                    r = f;
                    break;
                }
            }
        }
        return r;
    }

    private static var CLASS_FIELD_CACHE:Map<String, Map<String, ClassField>> = null;
    private static function cacheClassFields(c:ClassType) {
        if (CLASS_FIELD_CACHE != null) {
            return;
        }
        CLASS_FIELD_CACHE = new Map<String, Map<String, ClassField>>();
        var fullName = c.pack.join(".") + "." + c.name;

        var map = CLASS_FIELD_CACHE.get(fullName);
        if (map == null) {
            map = new Map<String, ClassField>();
            CLASS_FIELD_CACHE.set(fullName, map);
        }

        var ref = c;
        while (ref != null) {
            for (f in ref.fields.get()) {
                map.set(f.name, f);
            }

            if (ref.superClass != null) {
                ref = ref.superClass.t.get();
            } else {
                break;
            }
        }
    }

    // this is a _highly_ specialized version of "findField", that because we know
    // that we are running inside haxeui can make so assumptions and so big perf
    // improvements, most notably:
    //  * once we get to 'haxe.ui.core.ComponentCommon' we know we dont care anymore
    //  * we can cache all fields from 'haxe.ui.core.Component' and upwards
    //    this means that once we get to those classes we no longer need to 
    //    do any iterations, this leads to _huge_ performance increases that
    //    that scale (around 30 times faster!)
	static public function findFieldEx(c:ClassType, name:String):Null<ClassField> {
        var fullName = c.pack.join(".") + "." + c.name;
        if (fullName == "haxe.ui.core.Component") {
            if (CLASS_FIELD_CACHE != null) {
                var map = CLASS_FIELD_CACHE.get(fullName);
                if (map != null) {
                    return map.get(name);
                }
            } else {
                cacheClassFields(c);
            }
        }

        var field = c.fields.get().find(function(field) return field.name == name);

        if (fullName == "haxe.ui.core.ComponentCommon") {
            return field;
        }

		var field = if (field != null) field; else if (c.superClass != null) findFieldEx(c.superClass.t.get(), name); else null;
        return field;
	}

    public function hasField(name:String, recursive:Bool = false):Bool {
        if (classType == null) {
            return false;
        }
        if (recursive == true) {
            return findFieldEx(classType, name) != null;
        }
        return (findField(name) != null);
    }

    public function hasFieldSuper(name:String):Bool {
        if (classType == null || classType.superClass == null) {
            return false;
        }
        var superClassType = classType.superClass.t.get();
        return findFieldEx(superClassType, name) != null;
    }

    public function getFieldsWithMeta(meta:String):Array<FieldBuilder> {
        var fs = [];
        for (f in fields) {
            for (m in f.meta) {
                if (m.name == meta || m.name == ':${meta}') {
                    fs.push(new FieldBuilder(f, this));
                }
            }
        }
        return fs;
    }

    public function getFieldMetaValue(meta:String, paramIndex:Int = 0):String {
        var v = null;
        for (f in fields) {
            for (m in f.meta) {
                if (m.name == meta || m.name == ':${meta}') {
                    v = ExprTools.toString(m.params[paramIndex]);
                }
            }
        }
        return v;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Interfaces
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public function hasInterface(interfaceRequired:String):Bool {
        var has:Bool = false;
        switch (type) {
            case TInst(t, _):
                while (t != null) {
                    for (i in t.get().interfaces) {
                        var interfaceName:String = i.t.toString();
                        if (interfaceName == interfaceRequired) {
                            has = true;
                            break;
                        }
                    }

                    if (has == false) {
                        if (t.get().superClass != null) {
                            t = t.get().superClass.t;
                        } else {
                            t = null;
                        }
                    } else {
                        break;
                    }
                }
            case TAbstract(t, _):
                switch (t.get().type) {
                    case TInst(t, _):
                        while (t != null) {
                            for (i in t.get().interfaces) {
                                var interfaceName:String = i.t.toString();
                                if (interfaceName == interfaceRequired) {
                                    has = true;
                                    break;
                                }
                            }

                            if (has == false) {
                                if (t.get().superClass != null) {
                                    t = t.get().superClass.t;
                                } else {
                                    t = null;
                                }
                            } else {
                                break;
                            }
                        }
                    case _:    
                }
            case _:
        }

        return has;
    }

    public function hasDirectInterface(interfaceRequired:String):Bool {
        var has:Bool = false;
        switch (type) {
            case TInst(t, _):
                for (i in t.get().interfaces) {
                    var interfaceName:String = i.t.toString();
                    if (interfaceName == interfaceRequired) {
                        has = true;
                        break;
                    }
                }
            case TAbstract(t, _):
                switch (t.get().type) {
                    case TInst(t, _):
                        for (i in t.get().interfaces) {
                            var interfaceName:String = i.t.toString();
                            if (interfaceName == interfaceRequired) {
                                has = true;
                                break;
                            }
                        }
                    case _:    
                }
            case _:
        }

        return has;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Hierarchy
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public function hasSuperClass(classRequired:String):Bool {
        var has:Bool = false;
        switch (type) {
            case TInst(t, _):
                if (t.toString() == classRequired) {
                    has = true;
                } else {
                    while (t != null) {
                        if (t.get().superClass != null) {
                            t = t.get().superClass.t;
                            if (t.toString() == classRequired) {
                                has = true;
                                break;
                            }
                        } else {
                            t = null;
                        }
                    }
                }
            case TAbstract(t, _):
                switch (t.get().type) {
                    case TInst(t, _):
                        if (t.toString() == classRequired) {
                            has = true;
                        } else {
                            while (t != null) {
                                if (t.get().superClass != null) {
                                    t = t.get().superClass.t;
                                    if (t.toString() == classRequired) {
                                        has = true;
                                        break;
                                    }
                                } else {
                                    t = null;
                                }
                            }
                        }
                    case _:    
                }
            case _:
        }

        return has;
    }

    public var superClass(get, null):Null<{ t:Ref<ClassType>, params:Array<haxe.macro.Type> }>;
    private function get_superClass():Null<{ t:Ref<ClassType>, params:Array<haxe.macro.Type> }> {
        var superClass:Null<{ t:Ref<ClassType>, params:Array<haxe.macro.Type> }> = null;
        switch (type) {
            case TInst(t, _):
                superClass = t.get().superClass;
            case TAbstract(t, _):
                switch (t.get().type) {
                    case TInst(t, _):
                        superClass = t.get().superClass;
                    case _:    
                }
            case _:
        }
        return superClass;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Meta
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public function hasClassMeta(items:Array<String>):Bool {
        var r = false;
        for (item in items) {
            if (classType.meta.has(item) == true || classType.meta.has(':${item}') == true) {
                r = true;
                break;
            }
        }
        return r;
    }

    public function addMeta(name:String, params:Array<Expr> = null) {
        if (params == null) {
            params = [];
        }
        classType.meta.add(name, params, pos);
    }

    public function getClassMeta(name:String, index:Int = 0):MetadataEntry {
        if (hasClassMeta([name]) == false) {
            throw 'Meta not found: ${name}';
        }

        var meta = null;
        if (classType.meta.has(name)) {
            meta = classType.meta.extract(name);
        } else if (classType.meta.has(':${name}')) {
            meta = classType.meta.extract(':${name}');
        }

        return meta[index];
    }

    public function getClassMetaValues(name:String, index:Int = 0):Array<Dynamic> {
        var values = [];

        var meta = getClassMeta(name);
        for (p in meta.params) {
            values.push(metaParam(p));
        }

        return values;
    }

    public function getClassMetaValue(name:String, index:Int = 0, paramIndex:Int = 0):Dynamic {
        var meta = getClassMeta(name);
        var param = meta.params[paramIndex];
        var v = metaParam(param);
        return v;
    }

    private function metaParam(param:Expr):Dynamic {
        var v = null;
        switch (param.expr) {
            case EConst(CString(str)):
                v = str;
            case EConst(CIdent(str)):
                v = str;
            case _:
                v = ExprTools.toString(param);
        }
        return v;
    }

    public function hasFieldMeta(f:Field, items:Array<String>):Bool {
        var r = false;
        for (item in items) {
            for (m in f.meta) {
                if (m.name == item || m.name == ':${item}') {
                    r = true;
                    break;
                }
            }
        }

        return r;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Vars
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public function findVar(name:String):VarBuilder {
        var v = null;
        for (f in fields) {
            if (f.name == name) {
                switch (f.kind) {
                    case FVar(_):
                        v = new VarBuilder(f, this);
                        break;
                    default:
                }
            }
        }

        return v;
    }

    public function addVar(name:String, t:ComplexType, e:Expr = null, access:Array<Access> = null, meta:Metadata = null):Field {
        if (access == null) {
            if (StringTools.startsWith(name, "_")) {
                access = [APrivate];
            } else {
                access = [APublic];
            }
        }
        if (meta == null) {
            meta = [];
        }
        var newField = {
            name: name,
            doc: null,
            meta: meta,
            access: access,
            kind : FVar(t, e),
            pos : pos
        }
        fields.push(newField);
        return newField;
    }

    public function addProp(name:String, t:ComplexType, e:Expr = null, get:String = null, set:String = null, access:Array<Access> = null, meta:Metadata = null):Field {
        if (access == null) {
            if (StringTools.startsWith(name, "_")) {
                access = [APrivate];
            } else {
                access = [APublic];
            }
        }
        if (meta == null) {
            meta = [];
        }
        var newField = {
            name: name,
            doc: null,
            meta: meta,
            access: access,
            kind : FProp(get, set, t, e),
            pos : pos
        }
        fields.push(newField);
        return newField;
    }

    public function hasVar(name:String):Bool {
        return (findVar(name) != null);
    }

    public function removeVar(name:String) {
        var v = null;
        for (f in fields) {
            if (f.name == name) {
                switch (f.kind) {
                    case FVar(_):
                        v = f;
                        break;
                    default:
                }
            }
        }

        if (v != null) {
            fields.remove(v);
        }
    }

    public function getVarsWithMeta(meta:String):Array<VarBuilder> {
        var vars = [];
        for (f in fields) {
            switch (f.kind) {
                case FVar(v):
                    for (m in f.meta) {
                        if (m.name == meta || m.name == ':${meta}') {
                            vars.push(new VarBuilder(f, this));
                        }
                    }
                default:
            }
        }
        return vars;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Properties
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public function addGetter(name:String, t:ComplexType, e:Expr, access:Array<Access> = null, addVar:Bool = true, isOverride:Bool = false):FieldBuilder {
        if (e == null) {
            e = macro {}
        }
        if (access == null) {
            if (StringTools.startsWith(name, "_")) {
                access = [APrivate];
            } else {
                access = [APublic];
            }
        }

        if (addVar == true) {
            var field:Field = findField(name);
            if (field == null) {
                field = {
                    name: name,
                    doc: null,
                    meta: [],
                    access: access,
                    kind: FProp("get", "null", t),
                    pos: pos
                }
                fields.push(field);
            } else {
                var newKind;
                switch (field.kind) {
                    case FProp(existingGet, existingSet, existingType, existingExpr):
                        newKind = FProp("get", existingSet, existingType, existingExpr);
                    case _:
                }
                #if macro
                field.kind = newKind;
                #end
            }
        }

        var fn = findFunction('get_${name}');
        if (fn == null) {
            var access = [APrivate];
            if (isOverride == true) {
                access.push(AOverride);
            }
            fn = addFunction('get_${name}', e, t, access);
        } else {
            fn.fn.expr = e;
        }

        return new FieldBuilder(findField(name), this);
    }

    public function addSetter(name:String, t:ComplexType, e:Expr, access:Array<Access> = null, paramName:String = "value", addVar:Bool = true, isOverride:Bool = false):FieldBuilder {
        if (e == null) {
            e = macro {
                return value;
            }
        }
        if (access == null) {
            if (StringTools.startsWith(name, "_")) {
                access = [APrivate];
            } else {
                access = [APublic];
            }
        }

        if (addVar == true) {
            var field:Field = findField(name);
            if (field == null) {
                field = {
                    name: name,
                    doc: null,
                    meta: [],
                    access: access,
                    kind: FProp("null", "set", t),
                    pos: pos
                }
                fields.push(field);
            } else {
                var newKind;
                switch (field.kind) {
                    case FProp(existingGet, existingSet, existingType, existingExpr):
                        newKind = FProp(existingGet, "set", existingType, existingExpr);
                    case _:
                }
                #if macro
                field.kind = newKind;
                #end
            }
        }

        var fn = findFunction('set_${name}');
        if (fn == null) {
            var access = [APrivate];
            if (isOverride == true) {
                access.push(AOverride);
            }
            fn = addFunction('set_${name}', e, [{ name: paramName, type: t }], t, access);
        } else {
            fn.fn.expr = e;
        }

        return new FieldBuilder(findField(name), this);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Functions
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    public var ctor(get, null):FunctionBuilder;
    private function get_ctor():FunctionBuilder {
        return findFunction("new");
    }

    public function addFunction(name:String, e:Expr = null, args:Array<FunctionArg> = null, r:ComplexType = null, access:Array<Access> = null):FunctionBuilder {
        if (e == null) {
            e = macro {}
        }
        if (access == null) {
            if (StringTools.startsWith(name, "_")) {
                access = [APrivate];
            } else {
                access = [APublic];
            }
        }
        if (args == null) {
            args = [];
        }
        var newField:Field = {
            name: name,
            doc: null,
            meta: [],
            access: access,
            kind: FFun({
                params : [],
                args : args,
                expr: e,
                ret : r
            }),
            pos: pos
        }
        fields.push(newField);
        return findFunction(name);
    }

    public function findFunction(name:String):FunctionBuilder {
        var fn = null;
        for (f in fields) {
            if (f.name == name) {
                switch (f.kind) {
                    case FFun(ff):
                        fn = new FunctionBuilder(f, ff);
                        break;
                    default:
                }
            }
        }
        return fn;
    }

    public function findFunctionsWithMeta(meta:String):Array<FunctionBuilder> {
        var fns:Array<FunctionBuilder> = [];
        for (f in fields) {
            if (hasFieldMeta(f, [meta])) {
                switch (f.kind) {
                    case FFun(fn):
                        fns.push(new FunctionBuilder(f, fn));
                    default:
                }
            }
        }
        return fns;
    }

    public function hasFunction(name:String):Bool {
        return (findFunction(name) != null);
    }

    public function removeFunction(name:String) {
        var fn = null;
        for (f in fields) {
            if (f.name == name) {
                switch (f.kind) {
                    case FFun(_):
                        fn = f;
                        break;
                    default:
                }
            }
        }

        if (fn != null) {
            fields.remove(fn);
        }
    }

    public function addToFunction(name:String, e:Expr = null, cb:CodeBuilder = null, where:CodePos = null) {
        if (where == null) {
            where = CodePos.End;
        }
        var fn = findFunction(name);
        if (fn == null) {
            throw 'Could not find function: ${name}';
        }

        fn.add(e, where);
    }
}
