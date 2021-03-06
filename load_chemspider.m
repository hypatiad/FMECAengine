function data = load_chemspider(mol,varargin)
%LOAD_CHEMSPIDER load CHEMSPIDER properties
%   syntax: data = load_chemspider(mol)
%           data = load_chemspider(mol,'property1',value1,'property2',value2,...)
%   INPUTS:
%      mol: string or nx1 cell array of strings containing molecules, CAS,...
%      recognized properties/values
%         destination: destination folder (default=tempdir)
%           thumbnail: flag (default=true), thumbnail image of the chemcial structure
%           structure: flag (default=true), 640x480 PNG image of the chemcial structure (see imsize)
%              follow: flag (default=false), true to force to follow all references found
%                csid: flag (default=false), true if mol contain CSID (to be used internally)
%              imsize: 2x1 array coding for the image size of 2D structures (default = [640 480])
%            autocrop: flag (default=false)
%         orientation: 'horiz' or 'horizontal', 'vert' or vertical', 'none' (default)
%   OUTPUTS:
%       data: nx1 structure array with fields
%            CSID: number, Chemispider identifier
%           InChI: string 
%        InChIKey: string
%          SMILES: string
%             CAS: string or cell array of strings
%        Synonyms: cell array of strings
%      Properties: structure with named fields (Averagemass,...VapourPressure) and containing a structure
%                  with fields: value (numeric), unit and name
%  UserProperties: structure array
%       Thumbnail: filename of the PNG thumbnail
%       structure: filename of the PNG stucture image
%             url: ChemSpider URL
%    urlstructure: ChemSpider URL for the structure
%           links: list of links to other databases
%
%   Example: load_chemspider('2-nitrophenol','imsize',[1600,1200],'autocrop',true,'orientation','horiz')
%
%   NOTE: http://esis.jrc.ec.europa.eu/ provides additional ways to validate the quality of data stored in ChemSpider
%
%
%   SEE ALSO: LOAD_NIST, LOAD_NIST_IR, LOAD_NCBI, LOAD_NCBISTRUCT, LOAD_CHEMINDUSTRY

% MS 2.1 - 21/05/11 - INRA\Olivier Vitrac - rev. 06/10/13

%Revision history
% 22/05/11 vectorization, minor bugs
% 13/06/11 set 'not found'
% 20/06/11 add iupac, remove tags <p>, <wbr>, <nobr>
% 13/07/11 fix requests based on CAS numbers starting with many 0
% 21/07/11 add QuickMass
% 22/08/11 update QuickMass according to modifications introduced by ChemSpider in August 2011
% 11/01/12 update help with ESIS website
% 15/06/12 update quicklinks (including QuickMass), add imsize
% 19/09/13 add autocrop
% 05/10/13 works again to retrieve properties, extract links
% 06/10/13 add orientation

% default
keyword = {'thumbnail' 'structure'};
default = struct('thumbnail',true,'structure',true,'destination',tempdir,'csid',false,'follow',false,...
    'imsize',[640 480],'autocrop',false,'orientation','none');

% Configuration
token = '30c079d0-cedb-42a7-be40-6e8f9f2c0d75'; % Olivier Vitrac account
%engine = 'http://www.chemspider.com/Chemical-Structure.%s.html'; % before 19/09/2013
rooturl = 'http://www.chemspider.com';
engine = sprintf('%s/RecordView.aspx?id=%%s',rooturl);
imgengine = sprintf('%s/ImagesHandler.ashx?id=%%s&w=%%d&h=%%d',rooturl);
tag2remove = {'<wbr\s*/?>' '</?nobr>' '</?p>' '</?span.*?>' '</?wbr>' '</?strong>' '</?sup>' '</?sub>' '\r|\n' '\s+' '\&\#(\d+)\;'};
tagreplacement = {'','','','','','','','','',' ','${char(str2double($1))}'};
num = '^\s*([+-]?\s*\d+\.?\d*[eEdD]?[+-]?\d*)'; % number

%arg check
if nargin<1, error('one argument is required'); end
options = argcheck(varargin,default,keyword,'property');
if ~exist(options.destination,'dir'), error('Destination folder ''%s'' does not exist',options.destination), end
if ~exist(fullfile(find_path_toolbox('MS'),'@Search'),'file')
    dispf('WARNING:\tCHEMSPIDER Search service is being installed, please wait...')
    currentpath = pwd; cd(find_path_toolbox('MS')) %#ok<*MCCD>
    createClassFromWsdl('http://www.chemspider.com/Search.asmx?WSDL')
    cd(currentpath)
    dispf('\t CHEMSPIDER Search service has been installed.\n\tFollow this: <a href="http://www.chemspider.com/Search.asmx">link</a> for details')
end

% recursion
if iscell(mol)
    nmol = numel(mol);
    data = struct([]);
    for i=1:nmol
        dispf('CHEMSPIDER iteration %d/%d: %s',i,nmol,mol{i})
        tmp = load_chemspider(mol{i},options);
        if isempty(data), data = tmp; else data(end+1:end+length(tmp))=tmp; end
    end
    return
end

%% Simple Search
tstart = clock;
obj = Search; % Constructor
% fix request based on CAS numbers and starting with many 0 
if all(checkCAS(mol))
    moltmp = regexp(mol,'[1-9]{1}[0-9]{1,6}-\d{2}-\d','match');
    if isempty(moltmp), error('unable to interpret %s as a valid CAS number',mol); end
    if length(moltmp)>1
        dispf('WARNING: several CAS numbers have been found, only the first is used:')
        cellfun(@(cas) dispf('\t''%s'' matches ''%s''',cas,mol),moltmp)
    end
    mol = moltmp{1};    
end
if ~options.csid
    screen = dispb('','LOAD_CHEMSPIDER\tsimple search service initiated for ''%s''',mol);
    try
        csid = SimpleSearch(obj,mol,token);
    catch errtyp
        if strcmp(errtyp.identifier,'MATLAB:unassignedOutputs'),
            dispb(screen,'WARNING LOAD_CHEMSPIDER: unable to find any valid CSID for %s',mol);
            data = struct([]); return
        else
            rethrow(errtyp)
        end
    end
    if isempty(csid), data = []; dispf('\t''%s'' not found',mol); return, end
    if iscell(csid.int)
        dispb(screen,'LOAD_CHEMSPIDER\t %d assessions found for ''%s''',length(csid.int),mol); screen='';
        if options.follow
            data = load_chemspider(csid.int,argcheck({'csid',true},options));
            return
        else csid = csid.int{1};
        end
    else    csid = csid.int;
    end
    screen = dispb(screen,'LOAD_CHEMSPIDER\t get information for ChemSpiderID=%s (''%s'')',csid,mol);
else
    screen = dispb('','LOAD_CHEMSPIDER\tuse the following ChemSpiderID ''%s''',mol);
    if isnumeric(mol), mol = num2str(mol); end
    if isempty(regexp(mol,'^\s*\d+\s*$','match','once')), error('invalid CSID ''%s''',mol), end
    csid = mol;
end
nfo = GetCompoundInfo(obj,csid,token); % first information

%% Extract thumbnail
if options.thumbnail
    screen = dispb(screen,'LOAD_CHEMSPIDER\t load thumbnail for ChemSpiderID=%s (''%s'')',csid,mol);
    thumbnailfile = fullfile(options.destination,sprintf('%s.thumb.png',csid));
    base64string=GetCompoundThumbnail(obj,csid,token);
    encoder = org.apache.commons.codec.binary.Base64;
    img = encoder.decode(uint8(base64string));
    fid = fopen(thumbnailfile,'w'); fwrite(fid,img,'int8'); fclose(fid);
else
    thumbnailfile = '';
end

%% Extract details
url = sprintf(engine,csid);
screen = dispb(screen,'LOAD_CHEMSPIDER\t connects to the main URL %s',url);
details = urlread(url); % nex engine returns a link "<h2>Object moved to here.</h2>"

% links in page (parsing)
% current parser recognize: chemspider, wikipedia, pdb, google, ncbi, msds, jrc links...
linksinpage = uncell(regexp(details,'href="(.*?)"','tokens'));
isforeignlink = cellfun(@isempty,regexp(linksinpage,'^/'));
chemspiderlinks = unique(regexprep(...
      linksinpage(~isforeignlink ... keep URLs starting with /
      & cellfun(@isempty,regexp(linksinpage,'\.aspx$')) ... remove the following extensions
      & cellfun(@isempty,regexp(linksinpage,'\.ashx\?')) ...
      & cellfun(@isempty,regexp(linksinpage,'\.ico$')) ...
      & cellfun(@isempty,regexp(linksinpage,'\.css$')) ...
      & cellfun(@isempty,regexp(linksinpage,'\.pdf$')) ...
      & cellfun(@isempty,regexp(linksinpage,'^/$')) ...
      & cellfun(@isempty,regexp(linksinpage,'^/blog')) ... remove additional
      & cellfun(@isempty,regexp(linksinpage,'^/rss')) ...
      & cellfun(@isempty,regexp(linksinpage,'^/ChemSpiderOpenSearch')) ...
      ),'^/',sprintf('%s/',rooturl)));
isexternalink = isforeignlink ...
    & cellfun(@isempty,regexp(linksinpage,'^javascript')) ... remove javascript links
    & cellfun(@isempty,regexp(linksinpage,'^#')) ... remove internal links
    & cellfun(@isempty,regexp(linksinpage,'^http://oas.rsc.org/|^http://www.rsc.org/|^http://my.rsc.org')) ... % remove add links
    & cellfun(@isempty,regexp(linksinpage,'^\'''));
iswiki = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://en.wiki'));
ispdb    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.rcsb.org/pdb/'));
isebi    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.ebi.ac.uk'));
isgoogle = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.google.com'));
ismsds   = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://msds'));
isalfa   = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.alfa.com'));
isjrc    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://esis.jrc.ec.europa.eu'));
isajpcell   = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://ajpcell'));
isncbi   = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.ncbi.nlm.nih.go'));
ismerck  = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.merckmillipore.com'));
isdoi    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://dx.doi.org'));
isepa    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.epa.gov'));
isacd    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.acdlabs.com/'));
ischem    = isexternalink & ~cellfun(@isempty,regexp(linksinpage,'^http://www.chemicalize.org'));
parsedlinks = struct(...
   'chemspider', {chemspiderlinks},...
    'wikipedia', {linksinpage(iswiki)},...
       'google', {linksinpage(isgoogle)},...     
          'jrc', {linksinpage(isjrc)},...
         'ncbi', {linksinpage(isncbi)},...
          'epa', {linksinpage(isepa)},...         
          'pdb', {linksinpage(ispdb)},...
          'ebi', {linksinpage(isebi)},...
         'msds', {linksinpage(ismsds)},...
         'alfa', {linksinpage(isalfa)},...
         'cell', {linksinpage(isajpcell)},...
      'acdlabs', {linksinpage(isacd)},...
  'chemicalize', {linksinpage(ischem)},...          
        'merck', {linksinpage(ismerck)},...
          'doi', {linksinpage(isdoi)},...
       'others', {linksinpage(isexternalink & ~iswiki & ~isgoogle & ~isjrc & ~isncbi & ~isepa & ~ispdb & ~isebi & ~ismsds & ~isalfa & ~isajpcell & ~isacd & ~ischem & ~ismerck)} ...
       );
for link=fieldnames(parsedlinks)', if length(parsedlinks.(link{1}))<=1, parsedlinks.(link{1}) = char(parsedlinks.(link{1})); end, end 
      
% to be fixed / 19/09/2013 /// BUG fixed by Chemspider 05/10/2013
% linksinpage = uncell(regexp(details,'href="(.*?)"','tokens'));
% if length(redirectionlink)~=1, error('ChemSpider changed its policy, contact <a href="mailto:olivier.vitrac@agroparistech.fr">the developer</a>'), end
% details = urlread(redirectionlink{1});

% 2D structure
urlstructure = sprintf(imgengine,csid,options.imsize(1),options.imsize(2));
if options.structure
    screen = dispb(screen,'LOAD_CHEMSPIDER\t save 2D structure as image from URL %s',urlstructure);
    structurefile = fullfile(options.destination,sprintf('%s.png',csid));
    urlwrite(urlstructure,structurefile);
    if options.autocrop, pngtruncateim(structurefile,0,0,0,0); end
    if ~strcmpi(options.orientation,'none')
        imsize = imfinfo(structurefile);
        if (~isempty(regexpi(options.orientation,'^horiz')) && imsize.Width<imsize.Height), rotation = +90;
        elseif (~isempty(regexpi(options.orientation,'^vert')) && imsize.Width>imsize.Height), rotation = -90;
        else rotation =0;
        end
        if rotation, imwrite(imrotate(imread(structurefile),rotation,'nearest','loose'),structurefile); end
    end
else
    structurefile = '';
end
dispb(screen,'LOAD_CHEMSPIDER\t extraction of ChemSpiderID=%s (''%s'') completed in %0.4g s',csid,mol,etime(clock,tstart));

%% Synonyms and CAS
iupac = strtrim(regexprep(uncell(regexp(details,'<div id="iupac".*?>(.*?)</div>','tokens')),tag2remove,tagreplacement));
syn = strtrim(regexprep(uncell(regexp(details,'<p class="syn".*?>(.*?)</p>','tokens')),tag2remove,tagreplacement));
cas = regexp(syn,'([1-9]{1}[0-9]{1,6}-\d{2}-\d)','tokens');
cas = uncell(cas(~cellfun('isempty',cas)));
if ~iscellstr(cas), cas = uncell([cas{:}]); end % additional uncell
cas = unique(cas);

%% Quick Properties (to be modified each time ChemSpider change its HTML code)
quickformula = regexprep(uncell(regexp(details,'<a.*class="emp-formula".*?>(.*?)</a>','tokens')),tag2remove,tagreplacement);
% Before August 2011 (not working now since at least Aug 22, 2011)
% quickmass = regexprep(uncell(regexp(details,'<li class="quick-mass">(.*?)</li>','tokens')),tag2remove,tagreplacement);
% quickmassprop    = regexprep(strtrim(regexprep(uncell(regexp(quickmass,'<th class="prop_title".*?>(.*?)</th>','tokens')),[tag2remove {'</?a.*?>' ':'}],[tagreplacement {'' ''}])),'\s','');
% quickmassvalue   = cellfun(@(x) str2double(x),strtrim(regexprep(uncell(regexp(quickmass,'<td class="prop_value.*?">([0-9\.]*)[\sDa]*?</td>','tokens')),tag2remove,tagreplacement)),'UniformOutput',false);
% quickmass = cell2struct([quickformula;quickmassvalue],[{'formula'};quickmassprop],1);
% After August 2011
% quickmass = regexprep(uncell(regexp(details,'<li class="_quick-mass">(.*?)</li>','tokens')),tag2remove,tagreplacement);
% quickmassprop = uncell(regexp(quickmass,'^\s*(.*):','tokens')); quickmassprop = regexprep(quickmassprop,'\s+','_');
% quickmassvalue = uncell(regexp(quickmass,':\s*(.*) Da','tokens')); quickmassvalue = str2double(quickmassvalue{1});
% quickmass = cell2struct([quickformula;quickmassvalue],[{'formula'};quickmassprop],1);
% After June 14, 2012
quicklinks = regexprep(uncell(regexp(details,'<div class="quick-links">(.*?)</div>','tokens')),tag2remove,tagreplacement);
averagemass = uncell(regexp(quicklinks,'Average mass: (.+?) Da','tokens'));
monomass = uncell(regexp(quicklinks,'Monoisotopic mass: (.+?) Da','tokens'));
if isempty(quickformula), quickformula = {''}; end
if isempty(averagemass), averagemass = {''}; end
if isempty(monomass), monomass = {''}; end
quickmass = cell2struct([quickformula;averagemass;monomass],{'formula' 'molecularmass' 'isotpicmass'},1);

%% Properties
prop    = strtrim(regexprep(uncell(regexp(details,'<(td|th) class="prop_title".*?>(.*?)</(td|th)>','tokens')),[tag2remove {'</?a.*?>' ':'}],[tagreplacement {'' ''}]));
if ~isempty(prop)
    prop    = prop(:,2); % remove td|th
    value   = strtrim(regexprep(uncell(regexp(details,'<td class="prop_value.*?">(.*?)</td>','tokens')),tag2remove,tagreplacement));
    [valnum,stop]=regexp(value,num,'tokens','end');
    valnum  = cellfun(@(x) str2double(x),uncell(valnum),'UniformOutput',false);
    valunit = cellfun(@(x,k) strtrim(x(k+1:end)),value,stop,'UniformOutput',false);
    fprop = regexprep(prop,{'ACD/' '#' '\(' '\s|\)|\.'},{'' 'Num' 'AT' ''}); [~,iprop] = unique(fprop);
    prop = cell2struct(cellfun(@(v,u,n) struct('value',v,'unit',u,'name',n),valnum(iprop),valunit(iprop),prop(iprop),'UniformOutput',false),fprop(iprop),1);
else
    prop = '';
end

%% User properties
propuser = uncell(regexp(details,'<div.*?class="user_data_property_header_div".*?>(.*?)</div>','tokens'));
if ~isempty(propuser)
    propusername = strtrim(regexprep(uncell(regexp(propuser,'<span.*?>(.*)</span>','tokens')),':',''));
    propvalue = strtrim(regexprep(propuser,'<span.*?>.*?</span>',''));
    if ~isempty(propvalue)
        isnum = find(~cellfun('isempty',regexp(propvalue,[num '\s*$'],'once')));
        tmp = cellfun(@(x) str2double(x),propvalue(isnum),'UniformOutput',false);
        valid = cellfun(@(x) ~isnan(x),tmp);
        propvalue(isnum(valid)) = tmp(valid); 
    end
    propuser = struct('name',propusername,'value',propvalue);
else
    propuser = struct('name',{},'value',{});
end

%% Assembling
data = catstruct(nfo,struct('Name',iupac,'CAS',{cas'},'Synonyms',{syn'},'QuickMass',quickmass,'Properties',prop,'UserProperties',propuser,...
    'Thumbnail',thumbnailfile,'structure',structurefile,'url',url,'urlstructure',urlstructure,'links',parsedlinks));
if isfield(data,'CAS') && length(data.CAS)==1, data.CAS = data.CAS{1}; end
if isfield(data,'Synonyms') && length(data.Synonyms)==1, data.Synonyms = data.Synonyms{1}; end
data.CSID = str2double(data.CSID);
if ~isfield(data,'structure'), data.structure = structurefile; end
if ~isfield(data,'url'), data.url = url; end
if ~isfield(data,'urlstructure'), data.urlstructure = urlstructure; end
