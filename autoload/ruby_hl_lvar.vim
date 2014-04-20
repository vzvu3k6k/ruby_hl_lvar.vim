" this line is magic. "; <<-finish

let s:self_path=expand("<sfile>")

execute 'rubyfile '.s:self_path

" bufnr => match_id
let s:match_ids = {}

" return: [[var_name, row, col_start, col_end]...]
function! ruby_hl_lvar#extract_lvars(buffer) abort
  let bufnr = bufnr(a:buffer)
  if exists('s:ret')
    unlet s:ret
  endif
  execute 'ruby RubyHlLvar::Vim.extract_lvars_from '.bufnr
  let ret = s:ret
  unlet s:ret
  return ret
endfunction

function! ruby_hl_lvar#highlight(buffer) abort
	let bufnr = bufnr(a:buffer)
	let matches = map(ruby_hl_lvar#extract_lvars(a:buffer), '
		\ ''\%''.v:val[1].''l''.''\%''.v:val[2].''c''.repeat(''.'', strwidth(v:val[0]) - 1)
		\ ')
	if has_key(s:match_ids, bufnr) && s:match_ids[bufnr] > 0
		call matchdelete(s:match_ids[bufnr])
	endif
	let s:match_ids[bufnr] = matchadd('EasyMotionTarget', join(matches, '\|'))
    echo matches
endfunction

" Ruby {{{
finish

module RubyHlLvar
  module Vim
    def self.extract_lvars_from(bufnr)
      with_error_handling do
        source = ::Vim.evaluate("getbufline(#{bufnr}, 1, '$')").join("\n")
        return_to_vim 's:ret', RubyHlLvar::Extractor.new.extract(source).map{|(n,l,c)| [n,l,c+1]}
      end
    end

    def self.return_to_vim(var_name, content)
      ::Vim.command "let #{var_name} = #{content.inspect}"
    end

    def self.with_error_handling
      begin
        yield
      rescue => e
        ::Vim.message e
        e.backtrace.each do|l|
          ::Vim.message l
        end
        raise e
      end
    end
  end
end

require 'ripper'

module RubyHlLvar
  class Extractor
    # source:String -> [ [lvar_name:String, line:Numeric, col:Numeric]... ]
    def extract(source)
      sexp = Ripper.sexp(source)
      extract_from_sexp(sexp)
    end

    def extract_from_sexp(sexp)
      p = SexpMatcher
      _any = p::ANY
      _xs = p::ARRAY_REST

      _1 = p._1
      _2 = p._2
      _3 = p._3

      case sexp
      when m = p.match([:void_stmt])
        []
      when m = p.match([:program, _1])
        # root
        m._1.flat_map {|subtree| extract_from_sexp(subtree) }
      when m = p.match([:assign, [:var_field, [:@ident, _1, _2]], _any])
        # single assignment
        name, (line, col) = m._1, m._2
        [[name, line, col]]
      when m = p.match([:massign, _1, _2])
        # mass assignment
        handle_massign_lhs(m._1)
      when m = p.match([:var_ref, [:@ident, _1, [_2, _3]]])
        # local variable reference
        [[m._1, m._2, m._3]]
      when m = p.match([:binary, _1, _any, _2])
        extract_from_sexp(m._1) + extract_from_sexp(m._2)
      when m = p.match([:method_add_block, _any, [p.or(:brace_block, :do_block), p.or(nil, [:block_var, _1, _any]), _2]])
        # block args
        (m._1 ? handle_block_var(m._1) : []) +
          # block body
          m._2.flat_map {|subtree| extract_from_sexp(subtree) }
      when m = p.match([:string_literal, [:string_content, _xs&_1]])
        m._1.flat_map {|content|
          case content
          when m_ = p.match([:string_embexpr, _1])
            m_._1.flat_map {|expr| extract_from_sexp(expr) }
          when m_ = p.match([:@tstring_content, _any, _any])
            []
          else
            puts "WARN: Unsupported ast item: #{content.inspect}"
            []
          end
        }
      when m = p.match([:module, _any, [:bodystmt, _1, _any, _any, _any]])
        m._1.flat_map {|subtree| extract_from_sexp(subtree) }
      else
        puts "WARN: Unsupported ast item: #{sexp.inspect}"
        []
      end
    end

    private
      def handle_massign_lhs(lhs)
        p = SexpMatcher
        lhs.flat_map {|expr|
          case expr
          when m = p.match([:@ident, p._1, [p._2, p._3]])
            [[m._1, m._2, m._3]]
          when m = p.match([:mlhs_paren, p._1])
            handle_massign_lhs(m._1)
          else
            []
          end
        }
      end
      def handle_block_var(params)
        p = SexpMatcher
        if params && params[0] == :params
          params[1].map {|param|
            case param
            when m = p.match([:@ident, p._1, [p._2, p._3]])
              [m._1, m._2, m._3]
            else
              []
            end
          }
        else
          []
        end
      end
  end

  class SexpMatcher
    class SpecialPat
      def execute(match, obj); true; end

      def rest?
        false
      end

      def self.build_from(plain)
        case plain
        when SpecialPat
          plain
        when Array
          if plain.last.is_a?(SpecialPat) && plain.last.rest?
            Arr.new(plain[0..-2].map{|p| build_from(p) }, plain.last)
          else
            Arr.new(plain.map{|p| build_from(p) })
          end
        else
          Obj.new(plain)
        end
      end

      def &(rhs)
        And.new([self, rhs])
      end

      class Arr < self
        def initialize(pats, rest = nil)
          @pats = pats
          @rest = rest
        end

        def execute(mmatch, obj)
          return false unless obj.is_a?(Array)
          return false unless @rest ? (obj.size >= @pats.size) :  (obj.size == @pats.size)
          @pats.zip(obj).all? {|pat, o|
            pat.execute(mmatch, o)
          } && (!@rest || @rest.execute(mmatch, obj[@pats.size..-1]))
        end
      end

      class ArrRest < self
        def execute(mmatch, obj)
          true
        end
        def rest?
          true
        end
      end

      class Obj < self
        def initialize(obj)
          @obj = obj
        end

        def execute(mmatch, obj)
          @obj == obj
        end
      end

      class Any < self
        def execute(match, obj); true; end
      end

      class Group < self
        def initialize(index)
          @index = index
        end
        attr_reader :index
        def execute(mmatch, obj)
          mmatch[@index] = obj
          true
        end
      end

      class Or < self
        def initialize(pats)
          @pats = pats
        end
        def execute(mmatch, obj)
          @pats.any? do|pat|
            pat.execute(mmatch, obj)
          end
        end
        def rest?
          @pats.any?(&rest?)
        end
      end

      class And <self
        def initialize(pats)
          @pats = pats
        end
        def execute(mmatch, obj)
          @pats.all? do|pat|
            pat.execute(mmatch, obj)
          end
        end
        def rest?
          @pats.any?(&:rest?)
        end
      end
    end

    ANY = SpecialPat::Any.new
    GROUP = 100.times.map{|i| SpecialPat::Group.new(i) }
    ARRAY_REST = SpecialPat::ArrRest.new

    class MutableMatch
      def initialize(pat)
        @pat = pat
        @group = {}
      end

      def ===(obj)
        @pat.execute(self, obj)
      end

      def [](i)
        @group[i]
      end

      def []=(i, val)
        @group[i] = val
      end

      SexpMatcher::GROUP.each do|g|
        define_method "_#{g.index}" do
          self[g.index]
        end
      end
    end

    def self.match(plain_pat)
      MutableMatch.new(SpecialPat.build_from(plain_pat))
    end

    def self.or(*pats)
      SpecialPat::Or.new(pats.map{|p| SpecialPat.build_from(p) })
    end

    class <<self
      GROUP.each do|g|
        define_method "_#{g.index}" do
          g
        end
      end
    end

  end
end

" }}} "