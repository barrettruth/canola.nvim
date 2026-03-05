if exists("b:current_syntax")
  finish
endif

syn match canolaCreate /^CREATE\( BUCKET\)\? /
syn match canolaMove   /^  MOVE /
syn match canolaDelete /^DELETE\( BUCKET\)\? /
syn match canolaCopy   /^  COPY /
syn match canolaChange /^CHANGE /
" Trash operations
syn match canolaRestore /^RESTORE /
syn match canolaPurge /^ PURGE /
syn match canolaTrash /^ TRASH /

let b:current_syntax = "canola_preview"
