--> Copied from https://github.com/lune-org/docs/blob/0a1e5a/.lune/moonwave.luau

export type Source = {
	path: string,
	line: number,
}

export type FunctionParam = {
	name: string,
	desc: string,
	lua_type: string,
}

export type FunctionReturn = {
	desc: string,
	lua_type: string,
}

export type Function = {
	name: string,
	desc: string,
	params: { FunctionParam },
	returns: { FunctionReturn },
	function_type: string,
	tags: { string }?,
	ignore: boolean,
	private: boolean,
	source: Source,
}

export type Property = {
	name: string,
	desc: string,
	lua_type: string,
	tags: { string }?,
	ignore: boolean,
	source: Source,
}

export type Type = {
	name: string,
	desc: string,
	lua_type: string,
	ignore: boolean,
	private: boolean,
	fields: { Property },
	source: Source,
}

export type Item = {
	name: string,
	desc: string,
	functions: { Function },
	properties: { Property },
	types: { Type },
	source: Source,
}

return {}
