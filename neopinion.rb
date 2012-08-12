require 'rubygems'
require 'neography'
require 'engtagger'

AVERAGE_START_POSITION = 15
MAXIMUM_GAP = 3

@neo = Neography::Rest.new
@tagger = EngTagger.new 

# Each node keeps track of all sentences that it is a part of using a 
# sentence identiﬁer (SID) along with its position of occurrence in that sentence (PID). 
# (A1:10-16) Each node will thus carry a 
# 

# Create the graph
# node properties:
# - pri (Positional Reference Information) which is a list of {SID:PID} pairs
#   - sid (sentence identiﬁer) 
#   - pid (position of occurrence identifier)
# - vsn (valid start node)
# - ven (valid end node)
# 
def create_graph
  sentences = ["My phone calls drop frequently with the iPhone.", 
               "Great device, but the calls drop too frequently."]
  
  word_hash = Hash.new { |hash, key| hash[key] = [] }
  
  sentences.each_with_index do |sentence, sentence_index|
    word_path = []
    tokens = split_sentence(sentence) 
    max = tokens.size

    tokens.each_with_index do |token, token_index|
      is_end_node = valid_end_node(token)
      properties = token.merge({:ven => is_end_node})
      word_path <<  @neo.create_unique_node("word_index", "token", token[:word], properties)

      node_id = get_node_id(word_path[token_index])
      word_hash[node_id] << "#{sentence_index}:#{token_index}"

      @neo.add_node_to_index("word_tag", "tag", token[:tag], node_id) 
      
      if token_index >= 1 && token_index <= max
        rel = @neo.create_relationship("co_occurence", word_path[token_index - 1], word_path[token_index])
      end 
    end
  end         

  word_hash.each do |key, value|
    node_id = key
    properties = {:vsn => valid_start_node(value), :pri => value }
    @neo.set_node_properties(node_id, properties)
  end

 # Testing
 get_valid_sentences

end  

# Split a sentence by part of speech
# return lowercase word and general part of speech
# 
def split_sentence(sentence)
  @tagger.get_readable(sentence).downcase.split(' ').collect do |w| 
      {  
         :word => w.split('/')[0], 
         :tag => w.split('/')[1][0..1] 
      }
   end 
end

# Valid end nodes are nodes that have an average starting position 
# less than the parameter passed in.
#
def valid_start_node(positions, avg_start_position = AVERAGE_START_POSITION)
  positions.collect{|p| p.split(':')[1].to_f }.inject{ |sum, el| sum + el } / positions.size <= avg_start_position
end

# Valid end nodes are periods, commas and coordinating conjunctions (and, but).
#
def valid_end_node(token)
  ["pp", "cc"].include? token[:tag]
end

# Gets the node_id of a node
#
def get_node_id(node)
  node["self"].split('/').last
end


def get_valid_sentences
require 'net-http-spy'

# Net::HTTP.http_logger_options = {:verbose => true} # see everything
  @neo = Neography::Rest.new
  cypher = "START vq=node(*), vs =node:word_tag(tag='pp') 
            MATCH path = vq -[:co_occurence*]-> vs
             WHERE vq.vsn! = true
               AND vs.ven! = true
               AND length(path) > 2
             RETURN distinct extract(n in nodes(path) : [n.tag, n.word, n.pri]"
  cypher = "START vq=node(*), vs =node:word_tag(tag='pp') 
            MATCH path = vq -[:co_occurence*]-> vs
            WHERE vq.vsn! = true
              AND vs.ven! = true
              AND length(path) > 2
            RETURN distinct extract(n in nodes(path) : n.word), 
                            extract(n in nodes(path) : n.tag), 
                            extract(n in nodes(path) : n.pri)"
  result = @neo.execute_query(cypher)
  puts result.inspect    
end

# a set of directed edges such that:
# (1) vq is a VSN 
# (2) vs is a VEN and
# (3) W satisﬁes a set of well-formedness POS constraints.
# - 1. . ∗ (/nn) + . ∗ (/vb) + . ∗ (/jj) + .∗
# - 2. . ∗ (/jj) + . ∗ (/to) + . ∗ (/vb).∗
# - 3. . ∗ (/rb) ∗ . ∗ (/jj) + . ∗ (/nn) + .∗
# - 4. . ∗ (/rb) + . ∗ (/in) + . ∗ (/nn) + .∗
#
def valid_path_all
  "START vq = node(*)" + 
  "MATCH path = vq -[:co_occurence*0..15]-> w1 " + 
                  "-[:co_occurence*1..15]-> w2 " +
                  "-[:co_occurence*1..15]-> w3 " + 
                  "-[:co_occurence*0..15]-> vs " +
  "WHERE vs.vsn! = true " +
  "  AND ve.ven! = true " +
  "  AND ( (w1.tag! = 'nn' AND w2.tag! = 'vb' AND w3.tag! = 'jj' ) " +
  "     OR (w1.tag! = 'jj' AND w2.tag! = 'to' AND w3.tag! = 'vb' ) " +
  "     OR (w1.tag! = 'rb' AND w2.tag! = 'jj' AND w3.tag! = 'nn' ) " +
  "     OR (w1.tag! = 'rb' AND w2.tag! = 'in' AND w3.tag! = 'nn' ) ) " +
  "RETURN path"    
end


def valid_path_one
  "START vq = node(*)" + 
  "MATCH vq -[:co_occurence*0..*]-> w1 " + 
           "-[:co_occurence*1..*]-> w2 " +
           "-[:co_occurence*1..*]-> w3 " + 
           "-[:co_occurence*0..*]-> ve " +
  "WHERE vq.vsn = true " +
  "  AND vs.ven = true " +
  "  AND w1.tag = 'nn' " +
  "  AND w2.tag = 'vb' " +
  "  AND w3.tag = 'jj' "
end

def valid_path_two
  "START vq = node(*)"
  "MATCH vq -[:co_occurence*0..*]-> w1 " + 
           "-[:co_occurence*1..*]-> w2 " +
           "-[:co_occurence*1..*]-> w3 " + 
           "-[:co_occurence*0..*]-> ve " +
  "WHERE vq.vsn = true " +
  "  AND vs.ven = true " +
  "  AND w1.tag = 'jj' " +
  "  AND w2.tag = 'to' " +
  "  AND w3.tag = 'vb' "
end

def valid_path_two
  "START vq = node(*)"
  "MATCH vq -[:co_occurence*0..*]-> w1 " + 
           "-[:co_occurence*1..*]-> w2 " +
           "-[:co_occurence*1..*]-> w3 " + 
           "-[:co_occurence*0..*]-> ve " +
  "WHERE vq.vsn = true " +
  "  AND vs.ven = true " +
  "  AND w1.tag = 'jj' " +
  "  AND w2.tag = 'to' " +
  "  AND w3.tag = 'vb' "
end