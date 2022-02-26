import os
import streamlit as st
from streamlit_option_menu import option_menu
from dataclasses import dataclass
from streamlit_text_annotation import text_annotation
from st_aggrid import AgGrid, GridOptionsBuilder, GridUpdateMode
import pandas as pd
import plotly.express as px
import mining
import db_manager


@dataclass
class Target:
    word: str = ""
    layer: str = ""
    layer_value: str = ""


@dataclass
class SpecialValue:
    type: str = ""
    layer: str = ""
    values: str = ""


def annotation_page():
    os.makedirs(project_data_folder, exist_ok=True)
    mode = option_menu(None, ["Existing Projects", "New Project"], orientation="horizontal")
    if mode == "New Project":
        title = st.text_input("Project Title")
        uploaded_file = st.file_uploader("Upload an annotated file (JSON format)", type="json")
        if st.button("Create project"):
            if not title or len(title.strip()) < 3:
                st.error("Invalid project title")
                return
            if not uploaded_file:
                st.error("Please upload a file")
                return
            folder = os.path.join(project_data_folder, title)
            try:
                os.makedirs(folder)
            except FileExistsError:
                st.error(f"Project {title} already exists")
                return
            with open(os.path.join(folder, "corpus.json"), "wb") as f:
                f.write(uploaded_file.getvalue())
            st.session_state.project = {'title': title, 'folder': folder}
            st.success("Project successfully created")
    else:
        projects = [f for f in os.listdir(project_data_folder) if os.path.isdir(os.path.join(project_data_folder, f))]
        if projects:
            folder_name = st.selectbox("Select an existing project to work with", projects)
            if st.button("Open project"):
                st.session_state.project = {
                    'title': folder_name, 
                    'folder': os.path.join(project_data_folder, folder_name)
                }
                st.success("Project opened")
        else:
            st.markdown("**No projects currently exist**")

def get_db_manager():
    if "project" not in st.session_state:
        st.error("Please select a project first")
        return
    if 'db_manager' in st.session_state.project:
        manager = st.session_state.project['db_manager']
    else:
        manager = db_manager.DBManager(os.path.join(st.session_state.project['folder'], "db.sqlite3"))
        st.session_state.project['db_manager'] = manager
    return manager

def mine_patterns(name, config):
    manager = get_db_manager()
    manager.create_database(on_exist="ignore")
    folder = st.session_state.project['folder']
    json_path = os.path.join(folder, "corpus.json")
    task_id = manager.new_task(name, config)
    mining.mine_patterns(json_path, folder, config, store_in_database=True, task_id=task_id)

def extraction_page():
    token_type_mapping = {"coarse-grained POS": "upos", "fine-grained POS": "xpos"}

    association_measure_mapping = {'MI': "pmi", "MI2": "pmi2", "MI3": "pmi3",
                                "Log-Likelihood": "loglikelihood", "Delta-P": "delta-p", "Log Dice": "logdice"}

    annotated_layers = ["lemma", "coarse-grained POS", "fine-grained POS", "supersense"]
    mode = option_menu(None, ["General Mode", "Target Mode", ], orientation="horizontal")
    task_name = st.text_input("Task name", placeholder="Unnamed")
    if not task_name:
        task_name = "Unnamed"
    if mode == "Target Mode":
        with st.expander("Target Definitions", expanded=True):
            if 'targets' not in st.session_state:
                st.session_state.targets = [Target()]
            left, right = st.columns([7, 3])
            if right.button("Add one more target"):
                st.session_state.targets.append(Target())
            for i, target in enumerate(st.session_state.targets):
                left, mid, right = st.columns([2, 2, 2])
                target.word = left.text_input("Target Word", placeholder="ask", key=f"word{i}")
                target.layer = mid.selectbox("Layer", [""] + annotated_layers[1:], key=f"word_layer{i}")
                target.layer_value = right.text_input("Layer Value", key=f"layer_value{i}")

    with st.expander("General Settings", expanded=True):
        left, mid, right = st.columns(3)
        association_measure = left.selectbox("Association Measure", association_measure_mapping.keys(), index=1)
        score_threshold = mid.number_input("Min Score Threshold", value=6.0, step=0.1, format="%.1f")
        min_pattern_freq_per_mill = right.number_input("Min Frequency per Million Words", value=10, step=1)
        token_types = st.multiselect("Token Types", annotated_layers, default=annotated_layers)
        for i, token_type in enumerate(token_types):
            if token_type in token_type_mapping:
                token_types[i] = token_type_mapping[token_type]
        left, right = st.columns(2)
        n_total_rounds = left.number_input("Number of rounds", value=10, step=10)
        n_per_round = right.number_input("Number of patterns to mine per round", value=10, step=10)

    with st.expander("Special Values", expanded=False):
        if 'special_values' not in st.session_state:
            st.session_state.special_values = []
        left, right = st.columns([7, 3])
        if right.button("Add one more value"):
            st.session_state.special_values.append(SpecialValue())
        for i, value in enumerate(st.session_state.special_values):
            left, mid, right = st.columns([3, 3, 7])
            value.type = left.selectbox("Type", ["Allowed", "Ignored"], key=f"value_type{i}")
            value.layer = mid.selectbox("Layer", annotated_layers, key=f"value_layer{i}")
            value.values = right.text_input("Values (separated by comma)", key=f"special_value{i}")

    left, mid, right = st.columns([3, 3, 3])
    if mid.button("Extract Constructions"):
        config = {
            "association_measure": association_measure_mapping[association_measure],
            "min_score_threshold": score_threshold,
            "min_pattern_freq_per_mill": min_pattern_freq_per_mill,
            "token_types": token_types,
            "n_total_rounds": n_total_rounds,
            "n_per_round": n_per_round,
        }
        if 'targets' in st.session_state:
            target_dict = {}
            for target in st.session_state.targets:
                if target.word:
                    if target.layer and target.layer_value:
                        target_dict[target.word] = {target.layer: target.layer_value}
                    else:
                        target_dict[target.word] = {}
            config['target_tokens'] = target_dict
        allowed_values = {}
        ignored_values = {}
        for value in st.session_state.special_values:
            dic = allowed_values if value.type == "Allowed" else ignored_values
            dic[value.layer] = [v.strip() for v in value.values.split(",")]
        if not allowed_values:
            allowed_values = {
                "upos": ["PRON", "NOUN"],
                "xpos": ["WH", "VBG", "VBN"],
                "deprel": ["ccomp"]
            }
        if not ignored_values:
            ignored_values = {
                "lemma": ["'", "a", "an", "the", "he", "his", "she", "her", "my", "our", "they", "their", "erm", "may", "should", "will", "shall", "can", "might", "must", "would", "ought", "could"]
            }
        config['allowed_values'] = allowed_values
        config['ignored_values'] = ignored_values
        print(config)
        with st.spinner("Mining patterns..."):
            mine_patterns(task_name, config)
        st.success("Patterns mined successfully!")

def show_pattern_in_context(manager, pattern, max_n=None, show_stats=False, key=None):
    results = manager.query_pattern(pattern, max_n)
    all_sent_data = []
    for i, result in enumerate(results['data']):
        tokens = []
        for t in result['tokens']:
            data = {'text': t[0]}
            if t[1]:
                data['labels'] = [t[1]]
            tokens.append(data)
        all_sent_data.append({'tokens': tokens, "labelOrientation": "vertical"})
        if max_n and i == max_n - 1:
            break
    if show_stats:
        if 'token_stats' in results:
            st.write(results['token_stats'])
    text_annotation(all_sent_data, key=key)


def explore_page():
    try:
        manager = get_db_manager()
        tasks = manager.get_all_tasks()
        task_info = [f"{t['id']} ({t['name']})" for t in tasks]
        st.subheader("Extracted Constructions")
        left, right = st.columns([1, 3])
        task_id = left.selectbox("Task", task_info)
        df = manager.get_pattern_df(task_id=int(task_id.split(" ")[0]))
    except Exception as e:
        st.error(f"Error: {e}")
        return
    # df = df.drop(["left", "right"], axis=1)
    gb = GridOptionsBuilder.from_dataframe(df)
    gb.configure_selection('multiple', use_checkbox=True, rowMultiSelectWithClick=True)
    grid_options = gb.build()
    response = AgGrid(df, gridOptions=grid_options, height="250px", update_mode="SELECTION_CHANGED")
    selected_rows = response['selected_rows']
    df_selected = pd.DataFrame(selected_rows)
    # df_selected = df_selected.melt(id_vars=['form'], value_vars=['count', 'score'], var_name="type")
    mode = option_menu(None, ["Visulization", "Context"],icons=['file-bar-graph', 'body-text'], orientation="horizontal")
    df_selected['size'] = 10
    if mode == "Visulization":
        if not selected_rows:
            return
        fig = px.scatter(df_selected, x='count', y='score', color='form', size="size", title="Patterns")
        st.plotly_chart(fig, use_container_width=True)
        left, right = st.columns(2)
        with left:
            fig = px.bar(df_selected, x="form", y='count', color="form")
            fig.update_layout(xaxis={'showticklabels': False})
            st.plotly_chart(fig, use_container_width=True)
        with right:
            fig = px.bar(df_selected, x="form", y='score', color="form")
            fig.update_layout(xaxis={'showticklabels': False})
            st.plotly_chart(fig, use_container_width=True)
    else:
        for i, row in enumerate(selected_rows):
            with st.expander(f"{row['form']} ({row['count']})", expanded=True):
                left, mid, right = st.columns([3, 3, 4])
                with left:
                    max_lines = st.number_input("Max lines", value=3, step=1, key=f"max_lines{i}")
                with mid:
                    show_stats = st.selectbox("Show stats", ["No", "Yes"], key=f"show_stats{i}") == "Yes"
                show_pattern_in_context(manager, row['form'], max_n=max_lines, 
                show_stats=show_stats, key=f'context{i}')


def output_page():
    manager = get_db_manager()
    df = manager.get_pattern_df()
    st.header("Click the button below to download the patterns for the current project")
    st.download_button("Download", file_name="patterns.csv", data=df.to_csv(index=False))


if __name__ == "__main__":
    project_data_folder = "../projects"

    steps = ["Annotation", "Mining", "Explore", "Output"]

    with st.sidebar:
        st.title("Welcome to LCLearn")
        if 'project' in st.session_state:
            st.header(f"Current project: {st.session_state.project['title']}")
        step = option_menu("Steps", steps)

    if step == "Annotation":
        annotation_page()
    elif step == "Mining":
        extraction_page()
    elif step == "Explore":
        explore_page()
    elif step == "Output":
        output_page()