" File:          snipcloud.vim
" Author:        Valentin Dallmeier
" Version:       0.1
" Description:   snipcloud.vim gets you the power of the cloud for vim
"
"
if exists('snipcloud_loaded') || &cp || version < 700
	finish
endif
let snipcloud_loaded = 1

let s:mapping={'java':'snc:language:Java','vim':'snc:language:Vim'}
let s:proxyport='3001'
let s:proxyhost='127.0.0.1'

fun! TriggerSnippet()
	if exists('g:SuperTabMappingForward')
		if g:SuperTabMappingForward == "<tab>"
			let SuperTabKey = "\<c-n>"
		elseif g:SuperTabMappingBackward == "<tab>"
			let SuperTabKey = "\<c-p>"
		endif
	endif

	if pumvisible() " Update snippet if completion is used, or deal with supertab
		if exists('SuperTabKey')
			call feedkeys(SuperTabKey) | return ''
		endif
		call feedkeys("\<esc>a", 'n') " Close completion menu
		call feedkeys("\<tab>") | return ''
	endif

	if exists('g:snipPos') | return snipcloud#jumpTabStop(0) | endif

	let word = matchstr(getline('.'), '\S\+\%'.col('.').'c')
	for scope in [bufnr('%')] + split(&ft, '\.') + ['_']
		let [trigger, snippet] = s:GetSnippet(word, scope)
		" If word is a trigger for a snippet, delete the trigger & expand
		" the snippet.
		if snippet != ''
			let col = col('.') - len(trigger)
			sil exe 's/\V'.escape(trigger, '/\.').'\%#//'
			return snipcloud#expandSnip(snippet, col)
		endif
	endfor

	if exists('SuperTabKey')
		call feedkeys(SuperTabKey)
		return ''
	endif
	return "\<tab>"
endf

fun! BackwardsSnippet()
	if exists('g:snipPos') | return snipcloud#jumpTabStop(1) | endif

	if exists('g:SuperTabMappingForward')
		if g:SuperTabMappingBackward == "<s-tab>"
			let SuperTabKey = "\<c-p>"
		elseif g:SuperTabMappingForward == "<s-tab>"
			let SuperTabKey = "\<c-n>"
		endif
	endif
	if exists('SuperTabKey')
		call feedkeys(SuperTabKey)
		return ''
	endif
	return "\<s-tab>"
endf

fun s:ReplaceEscapes(contents) 
        let result = []
        let regex = '\${\([^}]*\)}'
        for content in a:contents
                let escaped = substitute(content, '\\n', '\n', 'g')
                let escaped = substitute(escaped, '\\"', '"', 'g')
                let lastMatchEnd = 0
                let more = 1
                let i = 0
                while (more)
                        let thematchlist = matchlist(escaped, regex, lastMatchEnd, 0)
                        let lastMatchEnd = matchend(escaped, regex, lastMatchEnd, 0)
                        if (len(thematchlist) > 0) 
                                let thematch = get(thematchlist, 0)
                                let variableName = get(thematchlist, 1)
                                let escaped = substitute(escaped, escape(thematch, '$'), '${'.(i+1).':'.variableName.'}', '')
                                let escaped = substitute(escaped, escape(thematch, '$'), '$'.(i+1), 'g')
                                let i += 1
                        else 
                                let more = 0
                        endif
                endw
                let result += [escaped.'${'.(i+1).'}']
        endfor
        return result
endf

fun s:MyTrim(word)
        return substitute(a:word,'^\s\+\|\s\+$','','g') 
endf

fun s:NormalizeWord(word)
	let word = s:MyTrim(a:word)
        if (len(word) == 0) | return '' | endif
        if (word == '.') | return '' | endif
        if (stridx(word, '(') != -1) | return '' | endif
        if (stridx(word, ')') != -1) | return '' | endif
        if (stridx(word, '!') != -1) | return '' | endif
        if (stridx(word, ',') != -1) | return '' | endif
        if (stridx(word, '>') != -1) | return '' | endif
        if (stridx(word, '<') != -1) | return '' | endif
        return word
endf

fun s:RecordSnippetUsage(snippetId)
        let querypath='snippetused'
        let query='http://'.s:proxyhost.':'.s:proxyport.'/'.querypath.'?snippetid='.a:snippetId
        let response=system('curl -s --request post '.query)
        return response
endf

" Check if word under cursor is snippet trigger; if it isn't, try checking if
" the text after non-word characters is (e.g. check for "foo" in "bar.foo")
fun s:GetSnippet(word, scope)
	let word = s:NormalizeWord(a:word) | let snippet = ''
        " First look for snippets in snipcloud
        if (len(word) > 0)
                let response = s:searchSnippetsInCloud(word)
                let contents = s:ReplaceEscapes(s:parseJsonValues(response, 'content'))
                let ids = s:parseJsonValues(response, 'id')
                let names = s:parseJsonValues(response, 'name')
                "If exactly one snippet is found
                if (len(ids) == 0) | return [word, ''] | endif
                if (len(ids) == 1)
                        call s:RecordSnippetUsage(get(ids, 0))
                        return [word, get(contents, 0)]
                else 
                        let snippetIndex = s:ChooseSnippet(names, contents, ids)
                        if (snippetIndex >= 0 && snippetIndex < len(ids))
                                call s:RecordSnippetUsage(get(ids, snippetIndex))
                                return [word, get(contents, snippetIndex)]
                        else
                                return [word, '']
                        endif
                endif 
        endif
        return [word, '']
endf

fun s:ChooseSnippet(names, contents, ids)
	let snippet = []
	let i = 1
        for name in a:names 
                if (len(s:MyTrim(name)) > 0)
                        let snippet += [i.'. '.name]
                else
                        let snippet += [i.'. [Unnamed Snippet]']
                endif
                let i += 1
        endfor
        let num = inputlist(snippet) - 1
        return num
endf

fun! s:parseJsonValues(jsonString, attributeName)
        let l:regex = '\v"'.a:attributeName.'" : "((\\"|[^"])*)"'
        let l:contents = []
        let l:index = 1
        let l:more = 1
        while l:more
                let l:thematch = matchlist(a:jsonString, l:regex, 0, l:index)
                if (len(l:thematch) > 0) 
                        let l:contents += [get(l:thematch, 1)] 
                else 
                        let l:more = 0 
                endif
                let l:index = l:index + 1
        endw
        return l:contents
endf

fun! s:urlEscape(word)
        return substitute(a:word, ':', '%3a', 'g')
endf

fun! s:searchSnippetsInCloud(word)
        let thetags=[a:word]
        if !empty(&ft)
                if (has_key(s:mapping, &ft)) 
                        let thetags+=[s:urlEscape(get(s:mapping, &ft))]
                endif
        endif
        let length=len(thetags)
        let i=0
        let querypath='searchsnippets'
        let query='http://'.s:proxyhost.':'.s:proxyport.'/'.querypath.'?offset=0\&query='
        for mytag in thetags
                let query=query.mytag
                if (i < length - 1) | let query=query.'%20%2b%20' | endif
                let i+= 1
        endfor
        let response=system('curl -s '.query)
        return response
endf


fun! s:GetVisual() range
        let reg_save = getreg('"')
        let regtype_save = getregtype('"')
        let cb_save=&clipboard
        set clipboard&
        normal! ""gvy
        let selection=getreg('"')
        call setreg('"', reg_save, regtype_save)
        let &clipboard = cb_save
        return selection
endf

fun! s:storeSnippet(name, tagList, content, sharing)
        let thetags = a:tagList
        let querypath='insertsnippet'
        let query='http://'.s:proxyhost.':'.s:proxyport.'/'.querypath
        if !empty(&ft)
                if (has_key(s:mapping, &ft)) 
                        let langtag = get(s:mapping, &ft)
                        if (len(thetags) > 0) 
                                 let thetags = thetags.','.langtag 
                        else 
                                 let thetags = langtag 
                        endif
                endif
        endif
        "let thecommand = 'curl -s '.query.' --data-urlencode "tags='.thetags.'" --data-urlencode '.shellescape('content='.a:content).' --data-urlencode "name='.a:name.'" --data-urlencode "statusid='.a:sharing.'" --data-urlencode "privateusage=0"'
        let thecommand = "curl -s ".query." --data-urlencode 'tags=".thetags."' --data-urlencode 'content=".a:content."' --data-urlencode 'name=".a:name."' --data-urlencode 'statusid=".a:sharing."' --data-urlencode 'privateusage=0'"
        let response=system(thecommand)
        echom 'Saved snippet with id '.response
endf

fun! CreateSnippet()
        let content = substitute(s:GetVisual(), '\\n', '\n', 'g')
        "let content =s:GetVisual()
        let name = input ('Enter name for snippet: ')
        let tagList = input ('Enter comma-separated list of tags for snippet: ')
        let sharingList = ['1: Private', '2: Public', '3: Shared']
        let sharing = inputlist(sharingList)
        call s:storeSnippet(name, tagList, content, sharing)
endf
"
" vim:noet:sw=4:ts=4:ft=vim
