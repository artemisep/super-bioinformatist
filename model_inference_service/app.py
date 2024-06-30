from flask import Flask, request, jsonify
import tensorflow as tf
import pandas as pd

app = Flask(__name__)

def load_model(model_path):
    return tf.keras.models.load_model(model_path)

def evaluate_model(model, dataset_path):
    dataset = pd.read_csv(dataset_path)
    predictions = model.predict(dataset)
    ground_truth = dataset['label'].values

    # Compute accuracy
    correct = sum([1 for pred, truth in zip(predictions, ground_truth) if pred == truth])
    accuracy = correct / len(ground_truth)

    return {'accuracy': accuracy}

@app.route('/evaluate', methods=['POST'])
def evaluate():
    model_path = request.json['model_path']
    dataset_path = request.json['dataset_path']

    model = load_model(model_path)
    results = evaluate_model(model, dataset_path)

    return jsonify(results)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
